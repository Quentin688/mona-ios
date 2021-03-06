//
//  AppDelegate.swift
//  mona-ios
//
//  Created by Paul Chaffanet on 2019-05-10.
//  Copyright © 2019 Paul Chaffanet. All rights reserved.
//

import UIKit
import CoreData
import SwiftyBeaver
import Foundation
import Photos

let log = SwiftyBeaver.self

struct AppData {
    static var context = CoreDataStack.mainContext
    static var artists = [Artist]()
    static var artworks = [Artwork]()
    static var badges = [Badge]()
    static var categories = [Category]()
    static var districts = [District]()
    static var materials = [Material]()
    static var subcategories = [Subcategory]()
    static var techniques = [Technique]()
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private var didStart = true
    
    private var timer : Timer?
    // If internet is slow, this is useful in order to not repeat the upload task multiple times.
    
    private enum Request {
        case photo
        case rating
        case comment
    }
    private var isCurrentlyUploading = [Int16 : [Request : Bool]]()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        setupLogger()
        setupPreferences()
        
        AppData.context.retainsRegisteredObjects = true
        
        // Mis là temporairement pour éviter la longueur de chargement à chaque lancement de l'application
        fetchData { result in
            switch result {
            case .success():
                self.updatePhotosArtworks(artworks: AppData.artworks)
                self.handleSuccess()
                AppData.artworks.forEach {
                    self.isCurrentlyUploading.updateValue([.photo : false, .rating : false, .comment : false ], forKey: $0.id)
                }
                self.timer = Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(self.uploadData), userInfo: nil, repeats: true)
            case .failure(let error):
                // Dire pourquoi y a erreur par message si nécessaire
                fatalError(error.localizedDescription)
            }
        }
        
        /*
        Uncomment ce bloc de code là si on veut fetch les data et construire la base de données sans utiliser celle préchargée.
        // Fetch Data
        // Inutile d'avoir un token valide pour cela
        fetchData { result in
            switch result {
            case .success():
                if !AppData.artworks.isEmpty {
                    self.updatePhotosArtworks(artworks: AppData.artworks)
                    
                    // Je dois attendre que tout charge
                    self.setupArtworks { result in
                        switch result {
                        case .success():
                            self.setupBadges { _ in
                                self.handleSuccess()
                            }
                        case .failure:
                            self.handleSuccess()
                        }
                    }
                }
                else {
                    self.setupArtworks { result in
                        switch result {
                        case .success():
                            self.setupBadges { result in
                                switch result {
                                case .success:
                                    self.handleSuccess()
                                case .failure(let error):
                                    // Dire pourquoi y a erreur si nécessaire
                                    fatalError(error.localizedDescription)
                                }
                            }
                        case .failure(let error):
                            // Dire pourquoi y a erreur si nécessaire
                            fatalError(error.localizedDescription)
                        }
                    }
                }
                return
            case .failure(let error):
                // Dire pourquoi y a erreur par message si nécessaire
                fatalError(error.localizedDescription)
            }
        }
        */
        
        return true
 
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        if !didStart {
            // J'update déjà au lancement de l'application
            updatePhotosArtworks(artworks: AppData.artworks)
        }
        didStart = false
        NotificationCenter.default.post(name: .applicationDidBecomeActive, object: nil)
        
        handlePhotoLibraryUsageStatus()
    }
    
    private func handlePhotoLibraryUsageStatus() {
        
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({ (status) in
                self.handlePhotoLibraryUsageStatus()
            })
        case .denied, .restricted:
            // Deal with it
            guard let visibleVC = UIApplication.topViewController() else {
                // home button pressed programmatically - to thorw app to background
                UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
                // terminaing app in background
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                    exit(EXIT_SUCCESS)
                })
                return
            }
            UIAlertController.presentMessage(from: visibleVC,
                                             title: NSLocalizedString("PhotoLibraryUsageTitle", tableName: "AppDelegate", bundle: .main, value: "", comment: ""),
                                             message: NSLocalizedString("PhotoLibraryUsageDescription", tableName: "AppDelegate", bundle: .main, value: "", comment: ""),
                                             okCompletion: {
                                                // home button pressed programmatically - to thorw app to background
                                                DispatchQueue.main.async {
                                                    UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
                                                    // terminaing app in background
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                                                        exit(EXIT_SUCCESS)
                                                    })
                                                }
            },
                                             presentCompletion: nil)
            break
        case .authorized:
            // All is good
            break
        @unknown default:
            break
        }
    }
    
    private func updatePhotosArtworks(artworks: [Artwork]) {
        for artwork in artworks {
            // Les photos sont ordonnées par ordre d'ajout (comme un tableau classique en fait)
            // La plus récente photo pour une œuvre est à la fin de artwork.photos
            guard let photosOrderedSet = artwork.photos else {
                continue
            }
            // On cast cet orderedSet en tableau de Photo car c'est plus simple pour les manipulations
            let photos = photosOrderedSet.array as! [Photo]
            // On vérifie que ce tableau contient des Photo, sinon on continue à l'artwork suivant
            guard !photos.isEmpty else {
                continue
            }
            
            // On préparer ensuite un dict [localIdentifier : Photo]
            // Le local identifier nous mène directement à l'objet photo
            var localIdentifiersPhotoDict = [String : Photo]()
            photos.forEach { photo in
                localIdentifiersPhotoDict[photo.localIdentifier] = photo
            }
            // On récupère toutes les clés (les local identifiers associés à l'artwork)
            let localIdentifiers = Array(localIdentifiersPhotoDict.keys)
            // On vérifie s'ils existent encore dans l'album photo MONA
            let localIdentifiersExist = MonaPhotosAlbum.shared.existInPhotoLibrary(localIdentifiers: localIdentifiers)
            guard   let localIdentifiersToRemoveSet = localIdentifiersExist[false],
                    !localIdentifiersToRemoveSet.isEmpty else {
                        continue
            }
            let photosToRemove = localIdentifiersToRemoveSet.map { localIdentifier in
                return localIdentifiersPhotoDict[localIdentifier]!
            }
            
            artwork.removeFromPhotos(photosToRemove)
        }
        do {
            try AppData.context.save()
        }
        catch {
            log.error("Failed to save context: \(error)")
            return
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Saves changes in the application's managed object context before the application terminates.
        //self.saveContext()
    }
    
    private func setupLogger() {
        let console = ConsoleDestination()
        log.addDestination(console)
    }
    
    private func setupPreferences() {
        UserDefaults.standard.defaultSetup()
    }
    
    private func fetchData(completion: @escaping (Result<Void, Error>) -> Void) {
        let artworksFetchRequest = NSFetchRequest<Artwork>(entityName: "Artwork")
        let artistsFetchRequest = NSFetchRequest<Artist>(entityName: "Artist")
        let badgesFetchRequest = NSFetchRequest<Badge>(entityName: "Badge")
        let categoriesFetchRequest = NSFetchRequest<Category>(entityName: "Category")
        let districtsFetchRequest = NSFetchRequest<District>(entityName: "District")
        let materialsFetchRequest = NSFetchRequest<Material>(entityName: "Material")
        let subcategoriesFetchRequest = NSFetchRequest<Subcategory>(entityName: "Subcategory")
        let techniquesFetchRequest = NSFetchRequest<Technique>(entityName: "Technique")
        do {
            AppData.artworks = try AppData.context.fetch(artworksFetchRequest)
            AppData.artists = try AppData.context.fetch(artistsFetchRequest)
            AppData.badges = try AppData.context.fetch(badgesFetchRequest)
            AppData.categories = try AppData.context.fetch(categoriesFetchRequest)
            AppData.districts = try AppData.context.fetch(districtsFetchRequest)
            AppData.materials = try AppData.context.fetch(materialsFetchRequest)
            AppData.subcategories = try AppData.context.fetch(subcategoriesFetchRequest)
            AppData.techniques = try AppData.context.fetch(techniquesFetchRequest)
            completion(.success(()))
        }
        catch let error as NSError {
            print("Could not fetch. \(error), \(error.userInfo)")
            completion(.failure(error))
        }
    }
    
    private func setupArtworks(completion: @escaping (Result<Void, Error>) -> Void) {
        MonaAPI.shared.artworksv3 { result in
            switch result {
            case .success(let artworksResponse):
                if var artworksData = artworksResponse.data {
                    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                    context.persistentStoreCoordinator = CoreDataStack.persistentStoreCoordinator
                    artworksData.createOrUpdate(into: context)
                    
                    let artworksFetchRequest = NSFetchRequest<Artwork>(entityName: "Artwork")
                    let artistsFetchRequest = NSFetchRequest<Artist>(entityName: "Artist")
                    let categoriesFetchRequest = NSFetchRequest<Category>(entityName: "Category")
                    let districtsFetchRequest = NSFetchRequest<District>(entityName: "District")
                    let materialsFetchRequest = NSFetchRequest<Material>(entityName: "Material")
                    let subcategoriesFetchRequest = NSFetchRequest<Subcategory>(entityName: "Subcategory")
                    let techniquesFetchRequest = NSFetchRequest<Technique>(entityName: "Technique")
                    
                    do {
                        try context.save()
                        AppData.context.reset()
                        AppData.artworks = try AppData.context.fetch(artworksFetchRequest)
                        AppData.artists = try AppData.context.fetch(artistsFetchRequest)
                        AppData.categories = try AppData.context.fetch(categoriesFetchRequest)
                        AppData.districts = try AppData.context.fetch(districtsFetchRequest)
                        AppData.materials = try AppData.context.fetch(materialsFetchRequest)
                        AppData.subcategories = try AppData.context.fetch(subcategoriesFetchRequest)
                        AppData.techniques = try AppData.context.fetch(techniquesFetchRequest)
                        completion(.success(()))
                    }
                    catch let error as NSError {
                        print("Save or fetch failed. \(error), \(error.userInfo)")
                        completion(.failure(error))
                    }
                    
                }
            case .failure(let artworksError):
                log.error(artworksError)
                log.error(artworksError.localizedDescription)
                completion(.failure(artworksError))
            }
        }
    }
    
    /*
    private func setupArtworks(completion: @escaping (Result<Void, Error>) -> Void) {
        MonaAPI.shared.artworks { result in
            switch result {
            case .success(let artworksResponse):
                if let artworksData = artworksResponse.data {
                    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                    context.persistentStoreCoordinator = CoreDataStack.persistentStoreCoordinator
                    artworksData.createOrUpdate(into: context)
                   
                    let artworksFetchRequest = NSFetchRequest<Artwork>(entityName: "Artwork")
                    let artistsFetchRequest = NSFetchRequest<Artist>(entityName: "Artist")
                    let categoriesFetchRequest = NSFetchRequest<Category>(entityName: "Category")
                    let districtsFetchRequest = NSFetchRequest<District>(entityName: "District")
                    let materialsFetchRequest = NSFetchRequest<Material>(entityName: "Material")
                    let subcategoriesFetchRequest = NSFetchRequest<Subcategory>(entityName: "Subcategory")
                    let techniquesFetchRequest = NSFetchRequest<Technique>(entityName: "Technique")
                    
                    do {
                        try context.save()
                        AppData.context.reset()
                        AppData.artworks = try AppData.context.fetch(artworksFetchRequest)
                        AppData.artists = try AppData.context.fetch(artistsFetchRequest)
                        AppData.categories = try AppData.context.fetch(categoriesFetchRequest)
                        AppData.districts = try AppData.context.fetch(districtsFetchRequest)
                        AppData.materials = try AppData.context.fetch(materialsFetchRequest)
                        AppData.subcategories = try AppData.context.fetch(subcategoriesFetchRequest)
                        AppData.techniques = try AppData.context.fetch(techniquesFetchRequest)
                        completion(.success(()))
                    }
                    catch let error as NSError {
                        print("Save or fetch failed. \(error), \(error.userInfo)")
                        completion(.failure(error))
                    }
                    
                }
            case .failure(let artworksError):
                log.error(artworksError)
                log.error(artworksError.localizedDescription)
                completion(.failure(artworksError))
            }
        }
    }*/
    
    private func setupBadges(completion: @escaping (Result<Void, Error>) -> Void) {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = CoreDataStack.persistentStoreCoordinator
        let fetchRequest = NSFetchRequest<Badge>(entityName: "Badge")
        do {
            let badges = try context.fetch(fetchRequest)
            var badgesDict = [Int16 : Badge]()
            badges.forEach { badge in
                badgesDict[badge.id] = badge
            }
            
            let badgeEntityDescription = NSEntityDescription.entity(forEntityName: "Badge", in: context)!
            let localizedStringEntityDescription = NSEntityDescription.entity(forEntityName: "LocalizedString", in: context)!
            
            for (id, dict) in badgesData {
                if badgesDict[id] != nil {
                    continue
                }
                let badge = Badge(entity: badgeEntityDescription, insertInto: context)
                badge.id = id
                let englishLocalizedStringName = LocalizedString(entity: localizedStringEntityDescription, insertInto: context)
                let frenchLocalizedStringName = LocalizedString(entity: localizedStringEntityDescription, insertInto: context)
                englishLocalizedStringName.language = Language.en
                frenchLocalizedStringName.language = Language.fr
                let name = dict["name"]! as! [Language : String]
                englishLocalizedStringName.localizedString = name[.en]!
                frenchLocalizedStringName.localizedString = name[.fr]!
                badge.addToLocalizedNames(englishLocalizedStringName)
                badge.addToLocalizedNames(frenchLocalizedStringName)
                badge.currentValue = Int16(dict["currentValue"]! as! Int)
                badge.targetValue = Int16(dict["targetValue"]! as! Int)
                badge.collectedImageName = dict["collectedImageName"]! as! String
                badge.notCollectedImageName = dict["notCollectedImageName"]! as! String
                let englishLocalizedStringComment = LocalizedString(entity: localizedStringEntityDescription, insertInto: context)
                let frenchLocalizedStringComment = LocalizedString(entity: localizedStringEntityDescription, insertInto: context)
                englishLocalizedStringComment.language = Language.en
                frenchLocalizedStringComment.language = Language.fr
                let comments = dict["comment"]! as! [Language : String]
                englishLocalizedStringComment.localizedString = comments[.en]!
                frenchLocalizedStringComment.localizedString = comments[.fr]!
                badge.addToComments(englishLocalizedStringComment)
                badge.addToComments(frenchLocalizedStringComment)
            }
            if context.hasChanges {
                try context.save()
            }
            let badgesFetchRequest = NSFetchRequest<Badge>(entityName: "Badge")
            AppData.badges = try AppData.context.fetch(badgesFetchRequest)
            completion(.success(()))
        }
        catch let error as NSError {
            print("Could not fetch. \(error), \(error.userInfo)")
            completion(.failure(error))
        }
        
    }
    
    
    @objc func uploadData() {
        // If a token exists
        if let token = UserDefaults.Credentials.get(forKey: .token), token != "" {
            let manager = PHImageManager.default()
            let option = PHImageRequestOptions()
            option.deliveryMode = .highQualityFormat
            option.isNetworkAccessAllowed = true
            option.version = .original
            option.isSynchronous = false
            
            for artwork in AppData.artworks {
                if artwork.isCollected {
                    if  !artwork.photoSent || !artwork.ratingSent || !artwork.commentSent,
                        !isCurrentlyUploading[artwork.id]![.photo]!,
                        let photosOrderedSet = artwork.photos,
                        let lastPhotoAdded = photosOrderedSet.lastObject as? Photo,
                        let asset = MonaPhotosAlbum.shared.fetchAsset(withLocalIdentifier: lastPhotoAdded.localIdentifier) {
                        
                        // Load image
                        // Get image from asset
                        manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFill, options: option, resultHandler: {
                            result, info in
                            if let image = result {
                                self.isCurrentlyUploading[artwork.id]![.photo] = true
                                MonaAPI.shared.artwork(id: Int(artwork.id), rating: Int(artwork.rating), comment: artwork.comment, photo: image) { result in
                                    self.isCurrentlyUploading[artwork.id]![.photo] = false
                                    switch result {
                                    case .success(_):
                                        log.info("Successful upload for artwork's photo with id: \(artwork.id).")
                                        artwork.photoSent = true
                                        artwork.ratingSent = true
                                        artwork.commentSent = true
                                        do {
                                            try AppData.context.save()
                                        }
                                        catch {
                                            log.error("Failed to save context: \(error)")
                                        }
                                    case .failure(let userArtworkError):
                                        // If there is any error, stop upload task until the app restart.
                                        self.timer?.invalidate()
                                        self.timer = nil
                                        log.error("Failed to upload photo for artwork with id: \(artwork.id).")
                                        log.error(userArtworkError)
                                        //log.error(userArtworkError.localizedDescription)
                                    }
                                }
                            }
                        })
                    }
                    
                    
                    
                    
                    
                    // Because PUT Request not working for multipart/form-data with Laravel (i guess)....
                    /*
                    if  artwork.photoSent == false,
                        !isCurrentlyUploading[artwork.id]![.photo]!,
                        let photosOrderedSet = artwork.photos,
                        let lastPhotoAdded = photosOrderedSet.lastObject as? Photo,
                        let asset = MonaPhotosAlbum.shared.fetchAsset(withLocalIdentifier: lastPhotoAdded.localIdentifier) {
                        
                        // Load image
                        // Get image from asset
                        manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFill, options: option, resultHandler: {
                            result, info in
                            if let image = result {
                                self.isCurrentlyUploading[artwork.id]![.photo] = true
                                MonaAPI.shared.artwork(id: Int(artwork.id), rating: nil, comment: nil, photo: image) { result in
                                    self.isCurrentlyUploading[artwork.id]![.photo] = false
                                    switch result {
                                    case .success(_):
                                        log.info("Successful upload for artwork's photo with id: \(artwork.id).")
                                        artwork.photoSent = true
                                        do {
                                            try AppData.context.save()
                                        }
                                        catch {
                                            log.error("Failed to save context: \(error)")
                                        }
                                    case .failure(let userArtworkError):
                                        log.error("Failed to upload photo for artwork with id: \(artwork.id).")
                                        log.error(userArtworkError)
                                        //log.error(userArtworkError.localizedDescription)
                                    }
                                }
                            }
                        })
                    }
                    
                    if artwork.ratingSent == false && !isCurrentlyUploading[artwork.id]![.rating]! {
                        isCurrentlyUploading[artwork.id]![.rating] = true
                        MonaAPI.shared.artwork(id: Int(artwork.id), rating: Int(artwork.rating), comment: nil, photo: nil) { (result) in
                            self.isCurrentlyUploading[artwork.id]![.rating] = false
                            switch result {
                            case .success(_):
                                log.info("Rating \"\(artwork.rating)\" sent successfully for artwork with id: \(artwork.id).")
                                artwork.ratingSent = true
                                do {
                                    try AppData.context.save()
                                }
                                catch {
                                    log.error("Failed to save context: \(error)")
                                }
                            case .failure(let userArtworkError):
                                log.error("Failed to send rating \"\(artwork.rating)\" for artwork with id: \(artwork.id).")
                                log.error(userArtworkError)
                                //log.error(userArtworkError.localizedDescription)
                            }
                        }
                    }
                    
                    if artwork.commentSent == false &&  !isCurrentlyUploading[artwork.id]![.comment]! {
                        isCurrentlyUploading[artwork.id]![.comment] = true
                        MonaAPI.shared.artwork(id: Int(artwork.id), rating: nil, comment: artwork.comment, photo: nil) { (result) in
                            self.isCurrentlyUploading[artwork.id]![.comment] = false
                            switch result {
                            case .success(_):
                                log.info("Comment sent \"\(artwork.comment!)\" successfully for artwork with id: \(artwork.id).")
                                artwork.commentSent = true
                                do {
                                    try AppData.context.save()
                                }
                                catch {
                                    log.error("Failed to save context: \(error)")
                                }
                            case .failure(let userArtworkError):
                                log.error("Failed to send comment \"\(artwork.comment!)\" for artwork with id: \(artwork.id).")
                                log.error(userArtworkError)
                                //log.error(userArtworkError.localizedDescription)
                            }
                        }
                    }
                     */
                }
            }
        }
        else if  let username = UserDefaults.Credentials.get(forKey: .username),
                 let password = UserDefaults.Credentials.get(forKey: .password) {
            MonaAPI.shared.login(username: username, password: password) { result in
                switch result {
                case .success(let loginResponse):
                    UserDefaults.Credentials.set(loginResponse.token, forKey: .token)
                case .failure(let httpError):
                // Show login error
                    log.error(httpError)
                    
                }
            }
        }
    }
    
    
    private func handleSuccess() {
        if  let _ = UserDefaults.Credentials.get(forKey: .username),
            let _ = UserDefaults.Credentials.get(forKey: .password) {
            UserDefaults.Credentials.set("", forKey: .token)
            DispatchQueue.main.async {
                self.showApp()
            }
        }
        else {
            // Show username choice view controller
            DispatchQueue.main.async {
                self.showUsernameChoice()
            }
        }
    }
    
    private func showApp() {
        let storyboard = UIStoryboard(name: "Tabbar", bundle: nil)
        let tabBarController = storyboard.instantiateViewController(withIdentifier: "TabBarController") as! TabBarController
        self.window?.rootViewController = tabBarController
        self.window?.rootViewController!.view.alpha = 0.0;
        UIView.animate(withDuration: 0.5, animations: {
            self.window?.rootViewController!.view.alpha = 1.0
        })
    }
    
    private func showUsernameChoice() {
        let storyboard = UIStoryboard(name: "RegisterLogin", bundle: nil)
        let usernameChoiceVC = storyboard.instantiateViewController(withIdentifier: "UsernameChoiceViewController") as! UsernameChoiceViewController
        self.window?.rootViewController = usernameChoiceVC
        self.window?.rootViewController!.view.alpha = 0.0;
        UIView.animate(withDuration: 0.5, animations: {
            self.window?.rootViewController!.view.alpha = 1.0
        })
    }

}
