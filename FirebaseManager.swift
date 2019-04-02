//
//  FirebaseManager.swift
//  PhotoTimeline
//
//  Created by Алексей on 05/03/2019.
//  Copyright © 2019 Алексей. All rights reserved.
//

import Foundation
import Firebase
import UIKit
import RNCryptor

class FirebaseManager {
    
    let journalCollectionName: String
    let journalEntryCollectionName: String
    let photosCollectionName: String

    var db: Firestore!
    var handle: AuthStateDidChangeListenerHandle?

    init() {
        db = Firestore.firestore()

        //set default values if the app starts for the first time
        FirebaseCredentials.setDefaultsValues()
        
        // set default names
        journalCollectionName = UserDefaults.standard.string(forKey: FirebaseCredentials.journalKey)!
        journalEntryCollectionName = UserDefaults.standard.string(forKey: FirebaseCredentials.entryKey)!
        photosCollectionName = UserDefaults.standard.string(forKey: FirebaseCredentials.photosKey)!
    }
    
    //MARK: is user logged in check.
    /**
     Check if a user logged in
     - parameter completion: an escaping completion block with result. True if a user logged in, false overwise.
     */
    func isUserlogedIn(completion:@escaping((_ result:Bool)->Void)) {
        
        // check if user logged in
        handle = Auth.auth().addStateDidChangeListener { (auth, user) in
            
            // if not - open FirebaseCredentials
            guard user != nil else {
                completion(false)
                print ("User does not logged in")
                return
            }
            print ("User logged in")
            completion(true)
        }
        
    }
    
    // MARK: remove user handle listener 
    /**
     Remove listener handler. It has to be called after isUserLoggedIn in viewWillAppear or similar.
     */
    func removeListener(){
        guard handle != nil else { return }
        Auth.auth().removeStateDidChangeListener(handle!)
    }
    
    //MARK: logout user form firebase
    /**
     Logout from the firebase.
     - parameter completion: an escaping completion block.
     */
    func logOut(completion:@escaping((Error?)->Void)) {
        do {
            try Auth.auth().signOut()
            completion(nil)
        } catch let err as NSError {
            completion(err)
        }
        
    }
    
    //MARK: login user into firebase
    /**
     Log in to the firebase.
     - parameter email: login
     - parameter password: password
     - parameter completion: an escaping completion block.
     */
    func logInUser(email:String,
                   password:String,
                   completion: @escaping(Error?)->Void){
        Auth.auth().signIn(withEmail: email,
                           password: password) { (result, error) in
                            //guard let strongRef = self else { return }
                            if let err = error {
                                completion(err)
                            }
                            completion(nil)
        }

    }
    
    //MARK: add a journal to firebase
    /**
     Create a root object in a specific collection.
     - parameter newJournal: a JournalRoot object
     - parameter completion: an escaping completion block
     */
    func addJournalRoot(_ newJournal:JournalRoot, completion: @escaping()->Void ) {
        var ref: DocumentReference?
        let dataDict = [
            "title": newJournal.title as Any,
            "creationDate": newJournal.creationDate as Any,
            "lastModifiedDate": newJournal.lastModifiedDate as Any,
            "numberOFCountries": newJournal.numberOFCountries as Any,
            "numberOfEntries": newJournal.numberOfEntries as Any,
            "entryID": newJournal.entryID
        ]
        
        
        ref = db.collection(journalCollectionName).document(newJournal.entryID)
        ref!.setData(dataDict, completion: {(error) in
            if error != nil {
                print("error:\(String(describing: error?.localizedDescription))")
            } else {
                print("Inserted successfully, ref:\(ref!.documentID)")
            }
            completion()
        })
    }
    
    //MARK: delete a journalRoot from Firebase
    /**
     Delete a root object from the Firebase.
     Level1 delete a root object from specific collection.
      Level2 delete entries from specific collection.
       Level3 delete photos from specific collection.
     - parameter journal: a journalRoot object for deleting
     - parameter completion: an escaping completion block
     */
    func deleteJournalRoot(_ journal: JournalRoot, completion: @escaping(Error?)->Void) {
        
        // save for futher using if a journal was deleted earlier
        let journalID = journal.entryID
        
        //[START Level1] delete the journalRoot itself
        db.collection(journalCollectionName).document(journal.entryID).delete() { [weak self] err in
            
            if err != nil {
                completion(err)
                return
            }
            print("journal \(journalID) was deleted")
            //[END Level1]
            
            
            //[START Level2] delete all related entries
            let batch = self!.db.batch()
            let ref = self!.db.collection(self!.journalEntryCollectionName)
                .whereField("journalRootRef", isEqualTo: journalID)
            
            // get the documents array
            ref.getDocuments(completion: { [weak self] (query, error) in
                if error != nil {
                    completion(error)
                    return
                }

                // delete every document
                for document in query!.documents {
                    batch.deleteDocument(document.reference)
                }
                
                // execute the request
                batch.commit(completion: { (error) in
                    if error != nil {
                        completion(error)
                        return
                    }
                    print("entries with journal \(journalID) was deleted")
                    //[END Level2]
                    
                    //[START Level3] delete all related photos
                    let batch1 = self!.db.batch()
                    let ref1 = self!.db.collection(self!.photosCollectionName)
                        .whereField("journalRootRef", isEqualTo: journalID)
                    ref1.getDocuments(completion: { (query, error) in
                        if error != nil {
                            completion(error)
                            return
                        }
                        for document in query!.documents {
                            batch1.deleteDocument(document.reference)
                        }
                        batch1.commit(completion: { (error) in
                            if error != nil {
                                completion(error)
                                return
                            }
                            completion(nil)
                            print("photos with journal \(journalID) was deleted")
                            //[END Level3]
                        })
                    })

                    
                    
                })
            })
            
            
        }
    }
    
    
    //MARK: change journalRoot fields. Every field is separate for testing.
    /**
     Change an JournalRoot object fields.
     */
    func changeJournalRootFields(object: JournalRoot,
                                 title: String?,
                                 creationDate: Date?,
                                 lastModifiedDate: Date?,
                                 numberOFCountries: Int?,
                                 numberOfEntries: Int?,
                                 entryID: String?,
                                 completion:@escaping(Error?)->Void) {
        let ref = db.collection(journalCollectionName).document(object.entryID)
        var fieldsToChange = [String:Any]()
        if title != nil { fieldsToChange["title"] = title }
        if creationDate != nil { fieldsToChange["creationDate"] = creationDate }
        if lastModifiedDate != nil { fieldsToChange["lastModifiedDate"] = lastModifiedDate }
        if numberOFCountries != nil { fieldsToChange["numberOFCountries"] = numberOFCountries }
        if numberOfEntries != nil { fieldsToChange["numberOfEntries"] = numberOfEntries }
        if entryID != nil { fieldsToChange["entryID"] = entryID }
        ref.updateData(fieldsToChange) { (error) in
            if error != nil {
                completion(error)
            } else {
                print("Updated successfully")
            }
            completion(nil)
        }
    }
    
    
    //MARK: get the journals root list
    /**
     Get all root objects
     - parameter completion: an escaping completion block with an array of JournalRoot objects
     */
    func getJornalRootList(completion: @escaping(Error?, [JournalRoot]?)->Void ) {
        let journalRef = db.collection(journalCollectionName)
        var results = [JournalRoot]()
        journalRef.getDocuments { (query, error) in
            if error != nil {
                completion(error, nil)
                return
            }
            for document in query!.documents {
                let newJournal = JournalRoot()
                let timeStamp = document["creationDate"] as! Timestamp
                newJournal.creationDate = timeStamp.dateValue()
                newJournal.title = document["title"] as! String
                newJournal.entryID = document["entryID"] as! String
                newJournal.numberOFCountries = document["numberOFCountries"] as! Int
                newJournal.numberOfEntries = document["numberOfEntries"] as! Int
                results.append(newJournal)
            }
            completion(nil, results)
        }
    }
    
    
    //MARK: save all images into document directory
    /**
     Save all images from firebase into document directory
     - parameter objectID: entryID for a nested JournalEntry object.
     - parameter completion: an escaping completion block
     - parameter error: escaping closure parameter. Not nil if something went wrong.
     - parameter largeName: large images names.
     - parameter thumbnailNames: thumbnail names.
     */
    func saveNestedImagesLocally(objectID:String, completion:@escaping(_ error:Error?, _ largeNames:[String], _ thumbnailNames:[String])->Void) {
        var largeImageNames = [String]()
        var smallImageNames = [String]()
        
        // check if a password exist
        guard let passw = getPassword() else {
            completion(PhotoTimelineError.emptyPasswordString, largeImageNames, smallImageNames)
            return
        }
        
        let ref = db.collection(photosCollectionName).whereField("journalEntryRef", isEqualTo: objectID)
        ref.getDocuments { (query, error) in
            if error != nil {
                completion(error, largeImageNames, smallImageNames)
                return
            }
            
            let documentDir = try! FileManager.default.url(for: .documentDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true)
            
            for imageRef in query!.documents {
                // save a large image locally
                let base64StringImage = imageRef["image"] as! String
                
                // check if possible to decrypt an image
                guard let encryptedImageData = Data(base64Encoded: base64StringImage),
                    let imageData = self.decryptImage(encryptedImageData, password: passw) else {
                        print("Decryption error")
                        largeImageNames.removeAll()
                        smallImageNames.removeAll()
                        completion(PhotoTimelineError.decryptionError, largeImageNames, smallImageNames)
                        return
                }
                
                let imageName = RealmManager.getRandomString()
                let urlToWrite = documentDir.appendingPathComponent(imageName)
                try! imageData.write(to: urlToWrite)
                largeImageNames.append(imageName)
                
                // save a small image locally
                let smallImage = ImageManager.resizeImage(image: UIImage(data: imageData)!,
                                                          target: ImageManager.thumbnailSize)
                let smallImageData = smallImage.jpegData(compressionQuality: 1.0)
                let smallImageName = "\(ImageManager.thumbnailPrefix)\(imageName)"
                let smallURLtoWrite = documentDir.appendingPathComponent(smallImageName)
                try! smallImageData?.write(to: smallURLtoWrite)
                smallImageNames.append(smallImageName)
                
                print("saved image:\(imageName) ...")
            }
            completion(nil, largeImageNames, smallImageNames)
        }
        
    }
    
    
    //MARK: get the nested collection list
    /**
     Get from the Firebase and create all nested JournalEntry objects and JournalRoot class
     - parameter object: object with nested classes
     - parameter completion: an escaping completion block with a list of all nested JournalEntry objects
     */
    func getNestedJournalEntryList(object: JournalRoot, completion:@escaping(Error?, [JournalEntry]?)->Void) {
        let ref = db.collection(journalEntryCollectionName)
            .whereField("journalRootRef", isEqualTo: object.entryID)
        var results = [JournalEntry]()
        ref.getDocuments { (query, error) in
            if error != nil {
                completion(error, nil)
                return
            }
            
            for document in query!.documents {
                let newEntry = JournalEntry()
                let creationDate = document["creationDate"] as! Timestamp
                let lastModifiedDate = document["lastModifiedDate"] as! Timestamp
                newEntry.creationDate = creationDate.dateValue()
                newEntry.lastModifiedDate = lastModifiedDate.dateValue()
                newEntry.descriptionText = document["descriptionText"] as! String
                newEntry.entryID = document["entryID"] as! String
                newEntry.locationLattitute = document["locationLattitute"] as! Double
                newEntry.locationLongitute = document["locationLongitute"] as! Double
                newEntry.locationName = document["locationName"] as! String
                newEntry.locationRegionID = document["locationRegionID"] as! String
                results.append(newEntry)
                
            }
            completion(nil, results)
        }
    }
    
    
    //MARK: save journal entry
    /**
     Save journal entry to the Firebase.

     Level1: delete previous photos from firebase.
       Level2: upload photos into `photos` collection of firebase.
         Level3: upload collection entry into firebase with photo names
     
     - parameter target: JournalRoot object where to find nested object
     - parameter object: a new JournalEntry nested object
     - parameter largeImages: an array of UIImage
     - parameter completion: execute completion block when an operation will be finished
     
     */
    func replaceNestedJournalEntry(target: JournalRoot,
                                object:JournalEntry,
                                largeImages:[UIImage],
                                completion: @escaping(Error?)->Void) {
        
        var ref: DocumentReference?
        let batch1 = db.batch()
        let batch2 = db.batch()
        var photoNamesRef = [String]()
        
        // check if a password was saved
        guard let passw = getPassword() else {
            completion(PhotoTimelineError.emptyPasswordString)
            return
        }
        
        //[START Level1]: delete previous photos
        let photosForDeleting = db.collection(photosCollectionName)
            .whereField("journalEntryRef", isEqualTo: object.entryID)
        
        photosForDeleting.getDocuments { (query, error) in
            if error != nil {
                completion(error)
                return
            }

            for document in query!.documents {
                batch1.deleteDocument(document.reference)
            }
            batch1.commit(completion: { (error) in
                if error != nil {
                    completion(error)
                    return
                }
                print("Photo deleted successfully")
                //[END Level1]
                
                //[START Level2]: add data into entries collection with random name
                
                for largeImage in largeImages {
                    
                    // check if possible to encrypt an image
                    guard let encryptedString = self.encryptImage(largeImage, password: passw) else {
                        completion(PhotoTimelineError.encryptionError)
                        return
                    }
                    
                    let randNumber = RealmManager.getRandomString()
                    photoNamesRef.append(randNumber)
                    let photoDict = [
                        "journalRootRef": target.entryID,
                        "journalEntryRef": object.entryID,
                        //"image": largeImage.jpegData(compressionQuality: 0.5)!.base64EncodedString(),
                        "image": encryptedString,
                        "imageName": randNumber
                    ]
                    ref = self.db.collection(self.photosCollectionName).document(randNumber)
                    batch2.setData(photoDict, forDocument: ref!)
                }
                batch2.commit {  (error) in
                    if error != nil {
                        completion(error)
                        return
                    }
                    print("Photo inserted successfully, ref:\(ref?.documentID ?? "nil")")
                    //[END Level2]
                    
                    
                    //[START Level3]: add data into journals collection
                    var entryDict = [
                        "journalRootRef": target.entryID as Any,
                        "creationDate": object.creationDate as Any,
                        "lastModifiedDate": Date(),
                        "descriptionText": object.descriptionText as Any,
                        "entryID": object.entryID as Any,
                        "locationName": object.locationName as Any,
                        "locationLattitute": object.locationLattitute as Any,
                        "locationLongitute": object.locationLongitute as Any,
                        "locationRegionID": object.locationRegionID as Any,
                        ]
                    
                    var index = 0
                    for photoName in photoNamesRef {
                        entryDict["image\(index)"] = photoName
                        index += 1
                    }
                    let dataRef = self.db.collection(self.journalEntryCollectionName).document(object.entryID)
                    dataRef.setData(entryDict, completion: { (error) in
                        if error != nil {
                            completion(error)
                            return
                        }
                        print("Collection inserted successfully, ref:\(ref?.documentID ?? "nil")")
                        completion(nil)
                        //[END Level3]
                        
                    })
                }
            })
        }
    }

    
    //MARK: Remove nested entry
    /**
     Remove all nested entries from a root object
     - parameter entry: an JournalRoot object
     - parameter completion: an escaping completion block
     */
    func removeNestedJournalEntry(entry:JournalEntry, completion: @escaping(Error?)->Void) {
        let ref = db.collection(journalEntryCollectionName).document(entry.entryID)
        ref.delete()
        let photosForDeleting = db.collection(photosCollectionName)
            .whereField("journalEntryRef", isEqualTo:entry.entryID)
        
        let batch = db.batch()
        photosForDeleting.getDocuments { (query, error) in
            if error != nil {
                completion(error)
                return
            }
            for photoRef in query!.documents {
                batch.deleteDocument(photoRef.reference)
            }
            
            batch.commit(completion: { (error) in
                if error != nil {
                    completion(error)
                    return
                }
                completion(nil)
            })
        }
        
    }

    
    //MARK: check if a root object exist
    /**
     Check if a root object exist.
     - parameter journalRootID: an JournalRoot entryID field.
     - parameter result: true if exist, false otherwise.
     */
    func isJournalRootExist(journalRootID:String, completion: @escaping((_ result:Bool)->Void)) {
        let results = db.collection(journalCollectionName).whereField("entryID", isEqualTo: journalRootID)
        results.getDocuments { (query, error) in
            if error != nil {
                completion(false)
            }
            if query!.documents.count > 0 {
                completion(true)
                return
            }
            completion(false)
        }
    }
   
    
    //MARK: add a nested object into a root object and save all to the Firebase
    /**
     Add a nested object into a root object and save all to the Firebase
     - parameter newJournalEntry: an new object for inserting.
     - parameter journalRootID: an entryID of a JournalRoot object
     - parameter completion: an escaping completion block
     */
    func addJournalEntry(_ newJournalEntry: JournalEntry,
                         journalRootID:String,
                         completion:@escaping(Error?)->Void) {
        let dataDict = [
            "journalRootID": journalRootID as Any,
            "creationDate": newJournalEntry.creationDate as Any,
            "lastModifiedDate": newJournalEntry.lastModifiedDate as Any,
            "descriptionText": newJournalEntry.descriptionText as Any,
            "entryID": newJournalEntry.entryID as Any,
            "LocationName": newJournalEntry.locationName as Any,
            "locationLongitute": newJournalEntry.locationLongitute as Any,
            "locationLattitute": newJournalEntry.locationLattitute as Any,
            "locationRegionID": newJournalEntry.locationRegionID as Any,
            "images":[],
            "thumbnails":[]

        ]
        let ref = db.collection("entries").document(newJournalEntry.entryID)
        ref.setData(dataDict) { (err) in
            if err != nil {
                completion(err)
                return
            }
            completion(nil)
        }
    }

    
    //MARK: encrypt an image
    /**
     Get a password.
     - returns: String if a password exist, nil otherwise.
     */
    private func getPassword()->String? {
        guard let password = UserDefaults.standard.string(forKey: FirebaseCredentials.encKey) else {
            return nil
        }
        if password == "" { return nil }
        return password
    }

    
    //MARK: encrypt an image
    /**
     A func for encrypting an image.
     - parameter image: An image for encrypting
     - parameter password: A password for encrypting
     - returns: String if possible to encrypt, nil otherwise.
     */
    private func encryptImage(_ image:UIImage, password:String) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.5) else { return nil }
        let result = RNCryptor.encrypt(data: imageData, withPassword: password)
        return result.base64EncodedString()
    }

    
    //MARK decrypt an imageData
    /**
     A func for encrypting an image.
     - parameter imageData: An image data for encrypting
     - parameter password: A password for encrypting
     - returns: Data if possible to decrypt, nil otherwise.
     */
    private func decryptImage(_ imageData:Data, password:String) -> Data? {
        do {
            let result = try RNCryptor.decrypt(data: imageData, withPassword: password)
            return result
        } catch let err as NSError {
            print("Decryption error:\(err.localizedDescription)")
            return nil
        }
    }

    
    //MARK: for testing
    
    func getJournalRootListID(completion: @escaping([String])->Void){
        let collectionName = UserDefaults.standard.string(forKey: FirebaseCredentials.journalKey)!
        let journalsRef = db.collection(collectionName)
        journalsRef.getDocuments { (query, error) in
            if error != nil {
                print("Error:\(String(describing: error?.localizedDescription))")
            }
            var result = [String]()
            for document in query!.documents {
                result.append(document.documentID)
            }
            completion(result)
        }
        
        
    }

    
}
