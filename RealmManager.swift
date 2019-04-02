//
//  RealmManager.swift
//  PhotoTimeline
//
//  Created by Alex on 05/03/2019.
//  Copyright © 2019 Alex. All rights reserved.
//

import Foundation
import RealmSwift
import Firebase

class RealmManager {
        
    
    //MARK: the generic func for getting all data
    /**
     Get a list of objects type <T: Object>
     - parameter type: type of an object
     */
    func getAll<T: Object>(type: T.Type) -> [T] {
        var result = [T]()
        do {
            let realm = try Realm()
            let journalResults = realm.objects(T.self)
            result = Array(journalResults)
            return result
        } catch let err as NSError  {
            print("Error in journal getting: \(err.description)")
            return result
        }
    }
    
    //MARK: the generic func for dataModel class creation
    /**
     Create an object of type <T: Object>
     - parameter creationClass: type of an object
     - returns: True if success, false otherwise.
     */
    func createClass<T: Object>(creationClass: T) -> Bool {
        do {
            //let genericClass = T()
            let realm = try Realm()
            try realm.write {
                realm.add(creationClass)
            }
            print("Journal added")
            return true
        } catch let err as NSError {
            print("Error in journal adding: \(err.description)")
            return false
        }
    }
    
    /*
    //MARK: the generic func for dataModel array of classes creation

    func createClass<T: Object>(creationClass: [T]) -> Bool {
        do {
            //let genericClass = T()
            let realm = try Realm()
            try realm.write {
                for classRef in creationClass {
                    realm.add(classRef)
                }
            }
            print("Journal added")
            return true
        } catch let err as NSError {
            print("Error in journal adding: \(err.description)")
            return false
        }
    }
     */

    
    //MARK: generic delete func
    /**
     Delete an object of type <T: Object>
     - parameter object: type of an object
     - returns: nil if success, return Error otherwise.
     */
    func deleteObject<T: Object>(object: T) -> Error? {
        do {
            let realm = try Realm()
            try realm.write {
                realm.delete(object)
            }
            print("Journal deleted")
            return nil
        } catch let err as NSError {
            print("Error in journal deleting: \(err.description)")
            return err
        }

    }

    
    //MARK: find a local journal with the same entryID and return it
    /**
     Find a JournalRoot object
     - parameter objectFromFirebase: a JournalRoot object
     - returns: nil error, a JournalRoot object if success
     */
    func findLocalRootData(objectFromFirebase: JournalRoot) -> JournalRoot? {
        do {
            let realm = try Realm()
            let result = realm.objects(JournalRoot.self).filter("entryID = '\(objectFromFirebase.entryID)'")
            if result.count == 0 { return nil }
            return result.first!
        } catch let err as NSError {
            print("Error in journal deleting: \(err.description)")
            return nil
        }
    }
    
    
    //MARK: replace JournalEntry data fields. Every field is separate for testing.
    /**
     Replace a JournalRoot fields
     - parameter object: a JournalRoot object
     */
    func replaceRootData(object: JournalRoot,
                         title: String?,
                         numberOFCountries: Int?,
                         numberOfEntries: Int?,
                         creationDate: Date?,
                         lastModifiedDate: Date?,
                         entryID: String?) {
        do {
            let realm = try Realm()
            try realm.write {
                if title != nil { object.title = title! }
                if numberOFCountries != nil { object.numberOFCountries = numberOFCountries! }
                if numberOfEntries != nil { object.numberOfEntries = numberOfEntries! }
                if lastModifiedDate != nil { object.lastModifiedDate = lastModifiedDate! }
                if entryID != nil { object.entryID = entryID! }
            }
        } catch let err as NSError {
            print("Error in replaceRootData: \(err.description)")
        }
    }
    
    
    //MARK: return a JournalRoot countries and Entries
    /**
     Return a JournalRoot countries and entries
     - parameter object: a JournalRoot object
     - returns: the first Int: contries, the second Int: entries
     */
    func calculateEntriesAndCountries(object: JournalRoot)-> (Int, Int) {
        let entries = object.entries.count
        let cntry = object.entries.filter({ $0.locationLongitute != 0.0 && $0.locationLattitute != 0.0 })
        return (cntry.count, entries)
    }
    
    
    //MARK: insert the journalEntry into the journalRoot
    /**
     Insert a journalEntry into a journalRoot
     - parameter target: a JournalRoot object
     - parameter object: a JournalEntry object
     - returns: an index of a new object if success, nil otherwise.
     */
    func addNestedObject(target:JournalRoot, object:JournalEntry)->Int? {
        do {
            let realm = try Realm()
            try realm.write {
                target.entries.append(object)
            }
            print("Object added")
            guard let result = target.entries.index(of: object) else {
                throw PhotoTimelineError.objectAddingError
            }
            return result
        } catch let err as NSError {
            print("Error in nested adding: \(err.description)")
            return nil
        }
    }
    
    //MARK: find local journalEntry
    /**
     Find a local journalEntry
     - parameter journal: a JournalRoot object
     - parameter objectFromFirebase: a JournalEntry object
     - returns: a JournalEntry object if success, nil otherwise.
     */

    func findLocalNestedData(journal: JournalRoot, objectFromFirebase: JournalEntry) -> JournalEntry? {
        do {
            let predictate = NSPredicate(format: "entryID == %@", objectFromFirebase.entryID)
            let realm = try Realm()
            let objects = realm.objects(JournalEntry.self).filter(predictate)
            guard objects.first?.creationDate != nil,
                objects.first?.lastModifiedDate != nil else { return nil }
            return objects.first
        } catch {
            return nil
        }
    }
    
    
    //MARK: remove selected the journalEntry from the journalRoot
    /**
     Find a local journalEntry
     - parameter target: a JournalRoot object
     - parameter object: a JournalEntry object
     - returns: an Error object if error, nil if success.
     */
    func removeNestedObject(target:JournalRoot, object:JournalEntry) -> Error? {
        do {
            let realm = try Realm()
            guard let indexOfObject = target.entries.index(of: object),
                object.isInvalidated == false else {
                    throw PhotoTimelineError.objectInvalidated
            }
            
            try realm.write {
                target.entries.remove(at: indexOfObject)
            }
            print("Nested object removed")
            return nil
        } catch let err as NSError {
            print("Error in nested removing: \(err.description)")
            return err
        }
    }
    
    //MARK: remove selected the journalEntry from the journalRoot
    /**
     Find a local journalEntry
     - parameter objectID: a JournalRoot entryID field
     - returns: an Error object if error, nil if success.
     */
    func removeNestedObject(objectID:String) -> Error? {
        do {
            let realm = try Realm()
            let results = realm.objects(JournalEntry.self).filter({ $0.entryID == objectID })
            try realm.write {
                realm.delete(results)
            }
            print("Nested object removed")
            return nil
        } catch let err as NSError {
            print("Error in nested removing: \(err.description)")
            return err
        }
    }

    //MARK: remove selected the journalEntry from the journalRoot
    /**
     Replace a JournalEntry object in the given a JournalRoot object
     - parameter rootJournal: a JournalRoot object
     - parameter newObject: a new JournalEntry object
     - parameter oldObject: an old JournalEntry object
     - returns: false if error, true if success.
     */
    func replaceNestedObject(rootJournal:JournalRoot, newObject:JournalEntry, oldObject: JournalEntry) -> Bool {
        do {
            let realm = try Realm()
            guard let index = rootJournal.entries.index(of: oldObject)  else {
                print("A nested object does not updated")
                return false
            }
            try realm.write {
                rootJournal.entries.replace(index: index, object: newObject)
            }
            print("A nested object updated")
            return true
        } catch let err as NSError {
            print("Error in updating a nested object: \(err.description)")
            return false
        }
    }
    
    
    //MARK: insert images in a JournalEntry object
    /**
     Insert images in a JournalEntry object
     - parameter object: a JournalEntry object
     - parameter imagesNames: an array of images names
     - parameter thumbnails: an array of thumbnails names
     - returns: false if error, true if success.
     */
    func insertImagesNamesIntoNestedObject(object: JournalEntry, imagesNames:[String], thumbnails:[String]) -> Bool {
        do {
            let realm = try Realm()
            try realm.write {
                object.imagesFilenames.removeAll()
                for index in 0 ..< imagesNames.count {
                    object.imagesFilenames.append(imagesNames[index])
                    object.thumbnails.append(thumbnails[index])
                }
            }
            return true
        } catch let err as NSError {
            print("Error in findind ID: \(err.description)")
            return false
        }

    }
    
    /*
    func createJournalEntry(data:[String:Any]) -> JournalEntry? {
        guard let creationDate = data["creationDate"] as? Timestamp,
            let lastModifiedDate = data["lastModifiedDate"] as? Timestamp,
            let entryID = data["entryID"] as? String else { return nil }

        let newEntry = JournalEntry()
        newEntry.creationDate = creationDate.dateValue()
        newEntry.lastModifiedDate = lastModifiedDate.dateValue()
        newEntry.entryID = entryID
        newEntry.descriptionText = data["descriptionText"] as? String ?? ""
        newEntry.locationLattitute = data["locationLattitute"] as? Double ?? 0.0
        newEntry.locationLongitute = data["locationLongitute"] as? Double ?? 0.0
        newEntry.locationName = data["locationName"] as? String ?? ""
        newEntry.locationRegionID = data["locationRegionID"] as? String ?? ""
        return newEntry
    }
 
    
    //MARK: check if currentID exist
    
    func doesCurrentIDExist<T: Object>(entryID:Int, object:T.Type) -> Bool {
        do {
            let realm = try Realm()
            let results = realm.objects(T.self).filter("entryID = \(entryID)")
            if results.count == 0 {
                print("id#\(entryID) does not exist")
                return false
            } else {
                print("id#\(entryID) is exist")
                return true
            }
        } catch let err as NSError {
            print("Error in findind ID: \(err.description)")
            return false
        }
    }
 
     */

    //MARK: get random number - for testing purporse. better approach: UUID().uuidString

    static func getRandomString() -> String {
        let time = Date().timeIntervalSince1970
        let randomString = Int.random(in: 0...99)
        return "\(randomString)-\(time)"
    }

    //MARK: create a realm list of objects
    
    func createList(_ array:[String]) -> List<String> {
        let result = List<String>()
        result.append(objectsIn: array)
        return result
    }
    
    //MARK: for testing
    
    func removeAllNestedObjects(in journal: JournalRoot) -> Bool {
        do {
            let realm = try Realm()
            try realm.write {
                journal.entries.removeAll()
            }
            print("All Nested object removed")
            return true
        } catch let err as NSError {
            print("Error in nested removing: \(err.description)")
            return false
        }
        
    }

    
}
    

