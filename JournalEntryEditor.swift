//
//  JournalEntryEditor.swift
//  PhotoTimeline
//
//  Created by Alex on 21/02/2019.
//  Copyright © 2019 Alex. All rights reserved.
//

import Foundation
import UIKit
import MapKit
import Photos
import Firebase



class JournalEntryEditor: UITableViewController, UICollectionViewDataSource, UICollectionViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    
    var journalRef: JournalRoot!
    var entryIndex: Int?
    
    var selectedCreationDate: Date?
    var selectedLocationName: String?
    var selectedLocationLattitude: Double?
    var selectedLocationLongitude: Double?
    var selectedLocationRegionID: String?
    var selectedImagesArray = [ImageEntry]()
    var firebaseManager = FirebaseManager()
    var hasBackgroundWork = false
    var editingModeOn = false
    
    let alertManager = AlertManager()
    let realmManager = RealmManager()
    let dateManager = DateManager()
    let datePicker = UIDatePicker()
    let toolbarDp = UIToolbar()
    let preventEdit = PreventEditDelegate()
    let closeSoftKeyboard = CloseSoftKeyboardDelegate()
    let imageManager = ImageManager()
    let imagePicker = UIImagePickerController()
    let maxImages = 6
    let thumbnailSize = CGSize(width: 400, height: 250)
    let normalSize = CGSize(width: 1920, height: 1080)

    
    @IBOutlet weak var creationDate: UILabel!
    @IBOutlet weak var journalName: UILabel!
    @IBOutlet weak var descriptionText: UITextView!
    @IBOutlet weak var addressTextField: UITextField!
    @IBOutlet var collectionViewRef: UICollectionView!
    @IBOutlet var saveButtonRef: UIButton!
    
    //the supplementary struct for collectionView
    class ImageEntry {
        var image: UIImage
        var path: URL?
        var thumbnail: UIImage
        var thumbnailPath: URL?
        var isSelected: Bool
        
        init(image: UIImage, path:URL, thumbnail:UIImage, thumbnailPath:URL){
            self.image = image
            self.path = path
            self.thumbnail = thumbnail
            self.thumbnailPath = thumbnailPath
            self.isSelected = false
        }

        init(image: UIImage, thumbnail:UIImage){
            self.image = image
            self.path = nil
            self.thumbnail = thumbnail
            self.thumbnailPath = nil
            self.isSelected = false
        }


        deinit {
            print("Structure deallocated")
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // check if user logged in and save handle
        firebaseManager.isUserlogedIn { [weak self] (isLogged) in
            if isLogged == false {
                guard let cntrl = self?.storyboard?.instantiateViewController(withIdentifier: "FirebaseCredentialsID") as? FirebaseCredentials else {
                    fatalError("Cannot connect a viewController")
                }
                self?.present(cntrl, animated: true, completion: nil)
            }
            
        }

        
        alertManager.registerNavigationView(view: self.navigationItem)

        //request access to the gallery
        let authorisationStatus = PHPhotoLibrary.authorizationStatus()
        switch authorisationStatus {
        case .authorized:
            print("Access granted")
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({ newStatus in
                if newStatus == PHAuthorizationStatus.authorized {
                    print("success")}
            })
        case .restricted:
            print("No access to album")
        case .denied:
            print("Permission Denied")
        }

        // if entry does not exist - create one
        if entryIndex == nil {
            
            selectedCreationDate = Date()

            //create the new entry
            let newEntry = JournalEntry()
            newEntry.creationDate = selectedCreationDate
            newEntry.entryID = RealmManager.getRandomString()
            newEntry.lastModifiedDate = selectedCreationDate

            // add new object
            entryIndex = realmManager.addNestedObject(target: journalRef, object: newEntry)
            
            alertManager.showSpinner(message: "Adding...")
            firebaseManager.addJournalEntry(newEntry, journalRootID: journalRef.entryID) { [weak self] (err) in
                if err != nil {
                    self?.alertManager.showOkDialogue(title: "Error",
                                                       message: err!.localizedDescription,
                                                       target: self)
                    
                }
                self?.alertManager.hideSpinner()
            }

        }
        
        // load default values
        selectedCreationDate = journalRef!.entries[entryIndex!].creationDate
        selectedLocationName = journalRef!.entries[entryIndex!].locationName
        selectedLocationLongitude = journalRef!.entries[entryIndex!].locationLongitute
        selectedLocationLattitude = journalRef!.entries[entryIndex!].locationLattitute
        selectedLocationRegionID = journalRef!.entries[entryIndex!].locationRegionID
        
        creationDate.text = dateManager.getShortDate(date: selectedCreationDate!, locale: Locale.current)
        addressTextField.text = selectedLocationName
        journalName.text = journalRef.title
        descriptionText.text = journalRef!.entries[entryIndex!].descriptionText
        
        // add gesture to the creationdatelabel
        let gs = UITapGestureRecognizer(target: self, action: #selector(showDatePicker))
        creationDate.addGestureRecognizer(gs)
        
        // add handler to textField and prevent edit
        addressTextField.addTarget(self, action: #selector(openSearchMap), for: .touchDragInside)
        addressTextField.delegate = preventEdit
        
        // force to close softKeyboard
        descriptionText.delegate = closeSoftKeyboard
        
        // add data source and delegate to the collectionview - show max 6 images
        collectionViewRef.dataSource = self
        collectionViewRef.delegate = self
        collectionViewRef.allowsMultipleSelection = true
        
        // add delegate to imapePicker for selecting images from the gallery
        imagePicker.delegate = self
        imagePicker.allowsEditing = true
        imagePicker.sourceType = .savedPhotosAlbum
        
        // add handler to button
        saveButtonRef.addTarget(self, action: #selector(saveJournalEntryHandler), for: .touchUpInside)
        
        
        // load images
        let fileNames = journalRef!.entries[entryIndex!].imagesFilenames
        let thumbnailsFilename = journalRef!.entries[entryIndex!].thumbnails
        for index in 0 ..< fileNames.count {
            
            let (img, imageURL) = ImageManager.composeImageFromFilename(fileNames[index])
            let (thumbnail, thumbnailURL) = ImageManager.composeImageFromFilename(thumbnailsFilename[index])
            
            guard img != nil,
                imageURL != nil,
                thumbnail != nil,
                thumbnailURL != nil  else {
                    print("Cannot create an image")
                    continue
            }
            
            let newEntry = ImageEntry(image: img!,
                                      path: imageURL!,
                                      thumbnail: thumbnail!,
                                      thumbnailPath: thumbnailURL!)
            selectedImagesArray.append(newEntry)
            
        }
        
    }
    
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // remove listener
        firebaseManager.removeListener()
        
    }
    
    //MARK: show an alert if background work exists
    
    @objc func backStep() {
        if hasBackgroundWork {
            let alert = UIAlertController(title: "Alert",
                                          message: "Some data could not be updated",
                                          preferredStyle: .alert)
            let closeAction = UIAlertAction(title: "Close anyway",
                                            style: .default,
                                            handler: {(action) in
                                                self.navigationController?.popViewController(animated: true)
            })
            let leaveAction = UIAlertAction(title: "Wait",
                                            style: .cancel,
                                            handler: nil)
            
            alert.addAction(closeAction)
            alert.addAction(leaveAction)
            self.present(alert, animated: true, completion: nil)
        }

        // clean images array and deallocate memory
        selectedImagesArray.removeAll()
        
        self.navigationController?.popViewController(animated: true)
    }

    
    //MARK: CollectionView: collectionViewDelegate method - getPictureList
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return selectedImagesArray.count + 1
    }
    
    //MARK: CollectionView: collectionViewDelegate method - getPictureList
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.row == selectedImagesArray.count {
            guard let cell = collectionViewRef.dequeueReusableCell(withReuseIdentifier: "JournalEditorAddImageID", for: indexPath) as? JournalEditorAddImage else {
                fatalError("Cannot connect a image cell")
            }
            if selectedImagesArray.count < maxImages {
                cell.addImageLabel.textColor = UIColor.white
                cell.backgroundColor = view.tintColor
            } else {
                cell.addImageLabel.textColor = UIColor.white
                cell.backgroundColor = #colorLiteral(red: 0.9081432819, green: 0.9082955718, blue: 0.9081231952, alpha: 1)
            }
            return cell
        }
        guard let cell = collectionViewRef.dequeueReusableCell(withReuseIdentifier: "JournalEditorImageCellID", for: indexPath) as? JournalEditorImageCell else {
            fatalError("Cannot connect a image cell")
        }
        cell.imageView.contentMode = .scaleAspectFill
        cell.imageView.image = selectedImagesArray[indexPath.row].thumbnail
        cell.borderWidth = 0.0
        cell.isSelected = false
        return cell
    }
    
    //MARK: CollectionView: collectionViewDelegate method - 'add image button' handler and select
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        print(indexPath.row)

        // open the gallery - the '+' button was pressed
        if indexPath.row == selectedImagesArray.count {
            
            // prevent selecting if maxPictures has reached
            if selectedImagesArray.count < maxImages && editingModeOn == false {
                self.navigationController?.present(imagePicker, animated: true, completion: nil)
            }
        
        // tapped on other cells
        } else {
            if let cell = collectionView.cellForItem(at: indexPath) {
                cell.isSelected = true
                cell.layer.borderWidth = 2.0
                cell.layer.borderColor = view.tintColor.cgColor
                cell.layer.cornerRadius = 5.0
                cell.clipsToBounds = true
                selectedImagesArray[indexPath.row].isSelected = true
                
                saveButtonRef.removeTarget(self, action: #selector(saveJournalEntryHandler), for: .touchUpInside)
                saveButtonRef.addTarget(self, action: #selector(removeSelectedImage), for: .touchUpInside)
                saveButtonRef.setTitle("Delete", for: .normal)
                editingModeOn = true
                
            }
        }
    }
    
    //MARK: CollectionView: collectionViewDelegate method - deselect

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        
        // prevent '+' button selected
        if indexPath.row == selectedImagesArray.count { return }
        
        if let cell = collectionView.cellForItem(at: indexPath) {
            cell.isSelected = false
            cell.layer.borderWidth = 0
            cell.layer.borderColor = UIColor.blue.cgColor
            selectedImagesArray[indexPath.row].isSelected = false
            
            if !isAnyCellSelected(array: selectedImagesArray) {
                saveButtonRef.removeTarget(self, action: #selector(removeSelectedImage), for: .touchUpInside)
                saveButtonRef.addTarget(self, action: #selector(saveJournalEntryHandler), for: .touchUpInside)
                saveButtonRef.setTitle("Save", for: .normal)
                editingModeOn = false
            }
        }
    }
    
    //MARK: UIImagePickerControllerDelegate: select and return the image
    
    @objc func imagePickerController(_ picker: UIImagePickerController,
                                     didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        if let img = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                        
            // save images in memory, not as a file
            let image = ImageManager.getAndResizeImage(image: img, size: .normalSize)
            let thumbnail = ImageManager.getAndResizeImage(image: img, size: .thumbnailSize)
            
            let entryRef = ImageEntry(image: image,
                                      thumbnail: thumbnail)

            selectedImagesArray.append(entryRef)
            
        }
        picker.dismiss(animated: true, completion: { [unowned self] in self.collectionViewRef.reloadData() })
    }
    
    
    
    @IBAction func deleteJournalEntry(_ sender: Any) {
        
        let lastDate = Date()
        
        //return object for del
        let objectForDel = journalRef.entries[entryIndex!]
        
        // remove local images
        ImageManager.removeImageLocally(Array(objectForDel.imagesFilenames))
        ImageManager.removeImageLocally(Array(objectForDel.thumbnails))
        
        // remove entry
        if let err = realmManager.removeNestedObject(target: journalRef, object: objectForDel) {
            alertManager.showOkDialogue(title: "Error",
                                        message: err.localizedDescription ,
                                        target: self)
        }
        
        // get countries and entries
        let (countries, entries) = realmManager.calculateEntriesAndCountries(object: journalRef)
        
        // update journalRoot data
        realmManager.replaceRootData(object: journalRef,
                                     title: nil,
                                     numberOFCountries: countries,
                                     numberOfEntries: entries,
                                     creationDate: nil,
                                     lastModifiedDate: lastDate,
                                     entryID: nil)

        // Delete an entry
        // Level1 - delete the nested journal entry
        //     Level2 - change the journal root

        // [START Level1]
        alertManager.showSpinner(message: "Deleting...")
        hasBackgroundWork = true
        firebaseManager.removeNestedJournalEntry(entry: objectForDel, completion: { [weak self] (error) in
            if error != nil {
                self?.alertManager.showOkDialogue(title: "Error",
                                                   message: error!.localizedDescription,
                                                   target: self)
                self?.alertManager.hideSpinner()
                self?.hasBackgroundWork = false
                return
            }
            // [END Level1]
            
            // [START Level2]
            self?.firebaseManager.changeJournalRootFields(
                object: self?.journalRef,
                title: self?.journalRef.title,
                creationDate: self?.journalRef.creationDate,
                lastModifiedDate: lastDate,
                numberOFCountries: countries,
                numberOfEntries: entries,
                entryID: self?.journalRef.entryID,
                completion: { [weak self] (error) in
                    if error != nil {
                        self?.alertManager.showOkDialogue(title: "Error",
                                                           message: error!.localizedDescription,
                                                           target: self)
                        self?.alertManager.hideSpinner()
                        self?.hasBackgroundWork = false
                        return
                    }

                    self?.alertManager.hideSpinner()
                    self?.hasBackgroundWork = false
                    self?.navigationController?.popViewController(animated: true)
                    // [END Level2]
            })
        })
        
        
        
    }
    
    //MARK: open the searchMap dialogue. Add links to the journalEntry and the textToFind
    
    @objc func openSearchMap(){
        let cntrl = self.storyboard?.instantiateViewController(withIdentifier: "SearchAddressID") as! SearchAddress
        cntrl.journalEntryRef = self
        cntrl.textToFind = selectedLocationName!
        self.navigationController?.pushViewController(cntrl, animated: true)
    }
    
    //MARK: open MapView and place the point
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let cntrl = segue.destination as! MapView
        let annotation = MKPointAnnotation()
        annotation.coordinate = CLLocationCoordinate2D(latitude: selectedLocationLattitude!,
                                                       longitude: selectedLocationLongitude!)
        annotation.title = selectedLocationName
        annotation.subtitle = dateManager.getShortDate(date: journalRef!.entries[entryIndex!].creationDate!,
                                                       locale: Locale.current)
        cntrl.regionID = selectedLocationRegionID!
        cntrl.journalEntryRef = self
        cntrl.editMode = true
        cntrl.selectedLocations = [annotation]
    }
    
    //MARK: the datePicker handler - show the picker
    
    @objc func showDatePicker(){
        
        datePicker.frame = CGRect(x: 0 ,
                                  y: view.frame.height - 300,
                                  width: view.frame.width,
                                  height: 250)
        datePicker.datePickerMode = .date
        datePicker.addTarget(self, action: #selector(selectDate), for: .valueChanged)
        datePicker.backgroundColor = UIColor.white

        toolbarDp.frame = CGRect(x: 0 ,
                                 y: view.frame.height-330.0,
                                 width: view.frame.width,
                                 height: 29)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done,
                                         target: self,
                                         action: #selector(doneDatePicker))
        let spaceArea = UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                                        target: self,
                                        action: nil)
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel,
                                           target: self,
                                           action: #selector(cancelDatePicker))
        toolbarDp.items = [cancelButton, spaceArea, doneButton]
        toolbarDp.barStyle = .default
        toolbarDp.isTranslucent = false
        toolbarDp.sizeToFit()
        toolbarDp.isUserInteractionEnabled = true
        
        self.view.addSubview(datePicker)
        self.view.addSubview(toolbarDp)
    }
    
    //MARK: the datePicker handler - date is selected
    
    @objc func selectDate(){
        creationDate.text = dateManager.getShortDate(date: datePicker.date, locale: Locale.current)
    }
    
    //MARK: the datePicker handler - cancelButtonHandler
    
    @objc func cancelDatePicker(){
        datePicker.removeFromSuperview()
        toolbarDp.removeFromSuperview()
    }
    
    //MARK done button handler - select date
    
    @objc func doneDatePicker(){
        selectedCreationDate = datePicker.date
        cancelDatePicker()
    }
    
    //MARK: when saveButton has 'Save' title - save JournalEntry
    
    @objc func saveJournalEntryHandler(){
        if alertManager.isNotUpdating() {
            saveEntry()
        }
    }

    //MARK: when saveButton has 'Save' title - delete selected images

    @objc func removeSelectedImage(){
        
        // remove images only from memory
        selectedImagesArray.removeAll(where: {( $0.isSelected == true )})
        collectionViewRef.reloadData()
        saveButtonRef.removeTarget(self, action: #selector(removeSelectedImage), for: .touchUpInside)
        saveButtonRef.addTarget(self, action: #selector(saveJournalEntryHandler), for: .touchUpInside)
        saveButtonRef.setTitle("Save", for: .normal)
        editingModeOn = false
    }

    //MARK: check if any cell was selected
    
    func isAnyCellSelected(array:[ImageEntry])->Bool {
        for entry in array {
            if entry.isSelected {
                return true
            }
        }
        return false
    }
    
    //MARK: the main finc for saving
    
    func saveEntry(){
        
        /*** OFFLINE part ***/
        
        hasBackgroundWork = true
        
        let lastDate = Date()
        
        let oldObject = journalRef!.entries[entryIndex!]
        
        let newObject = JournalEntry()
        newObject.entryID = oldObject.entryID
        newObject.descriptionText = descriptionText.text
        newObject.creationDate = selectedCreationDate
        newObject.locationLattitute = selectedLocationLattitude!
        newObject.locationLongitute = selectedLocationLongitude!
        newObject.locationName = selectedLocationName ?? ""
        newObject.locationRegionID = selectedLocationRegionID!
        newObject.lastModifiedDate = lastDate
        newObject.offline = oldObject.offline
        
        // clean up local directory before saving
        ImageManager.removeImageLocally(Array(oldObject.imagesFilenames))
        ImageManager.removeImageLocally(Array(oldObject.thumbnails))
        
        // create a new path for every image
        selectedImagesArray.forEach { (imageEntry) in
            let (imgURL, thumbnailURL) = ImageManager.saveImageAndThumbnail(image: imageEntry.image)
            imageEntry.path = imgURL
            imageEntry.thumbnailPath = thumbnailURL
        }
        
        // path is not nil here - extract filenames
        let selectedFileNames = selectedImagesArray.map { $0.path!.lastPathComponent }
        let selectedThumbnails = selectedImagesArray.map { $0.thumbnailPath!.lastPathComponent }

        // add images into journalEntry
        if realmManager.insertImagesNamesIntoNestedObject(object: newObject,
                                                           imagesNames: selectedFileNames,
                                                           thumbnails: selectedThumbnails ) == false {
            alertManager.showOkDialogue(title: "Error",
                                         message: PhotoTimelineError.impossibleInsertImagesIntoNestedObject.localizedDescription,
                                         target: self)
            return
        }
 
        // replace a nested object at given index
        
        if realmManager.replaceNestedObject(rootJournal: journalRef,
                                         newObject: newObject,
                                         oldObject: oldObject) == false {
            alertManager.showOkDialogue(title: "Error",
                                        message: PhotoTimelineError.impossibleReplaceNestedObject.localizedDescription,
                                        target: self)
            return
        }
        
        
        /* test
        let res1 = realmManager.findLocalNestedData(journal: journalRef, objectFromFirebase: newObject)
        let res2 = Array(res1!.imagesFilenames)
        let res3 = Array(res1!.thumbnails)
        let res4 = Array(newObject.imagesFilenames)
        let res5 = Array(newObject.thumbnails)
 
        let res6 = journalRef.entries
        for entry in res6 {
            print("Entry ID:\(entry.entryID)")
            for image in entry.thumbnails {
                print("image \(image)")
            }
        }
        */
        
        
        // get countries and entries
        let (countries, entries) = realmManager.calculateEntriesAndCountries(object: journalRef)
        
        if newObject.offline {
            hasBackgroundWork = false
            selectedImagesArray.removeAll()
            alertManager.hideSpinner()
            navigationController?.popViewController(animated: true)
            return
        }

        // update journalRoot data
        realmManager.replaceRootData(object: journalRef,
                                     title: nil,
                                     numberOFCountries: countries,
                                     numberOfEntries: entries,
                                     creationDate: nil,
                                     lastModifiedDate: lastDate,
                                     entryID: nil)

        
        /*** ONLINE part ***/
        
        // Level 1 - add data to the firebase
        //     Level 2 - replace the journalRoot and close the viewController
        alertManager.showSpinner(message: "Updating...")
        let largeImagesArray = selectedImagesArray.map { $0.image }
        
        // clean images array and deallocate memory
        selectedImagesArray.removeAll()

        // [START Level1] add data to firebase
        firebaseManager.replaceNestedJournalEntry(
            target: journalRef,
            object: newObject,
            largeImages: largeImagesArray,
            completion: { [weak self] (error) in
                if error != nil {
                    self?.alertManager.showOkDialogue(title: "Error",
                                                       message: error!.localizedDescription,
                                                       target: self)
                    self?.alertManager.hideSpinner()
                    return
                }
                // [END Level1]
                
                // [START Level2]
                self?.firebaseManager.changeJournalRootFields (
                    object: self?.journalRef,
                    title: nil,
                    creationDate: nil,
                    lastModifiedDate: lastDate,
                    numberOFCountries: countries,
                    numberOfEntries: entries,
                    entryID: nil,
                    completion: { [weak self] (error) in
                        if error != nil {
                            self?.alertManager.showOkDialogue(title: "Error",
                                                               message: error!.localizedDescription,
                                                               target: self)
                            self?.alertManager.hideSpinner()
                            return
                        }
                        self?.navigationController?.popViewController(animated: true)
                        self?.alertManager.hideSpinner()
                        self?.hasBackgroundWork = false
                        // [END Level2]
                })
        })
        
    }
    
}

