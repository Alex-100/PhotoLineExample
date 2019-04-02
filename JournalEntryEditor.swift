//
//  JournalEntryEditor.swift
//  PhotoTimeline
//
//  Created by Алексей on 21/02/2019.
//  Copyright © 2019 Алексей. All rights reserved.
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
    var handle: AuthStateDidChangeListenerHandle?
    var firebaseManager = FirebaseManager()
    var alertManager: AlertManager?
    var hasBackgroundWork = false
    
    let realmManager = RealmManager()
    let dateManager = DateManager()
    let datePicker = UIDatePicker()
    let toolbarDp = UIToolbar()
    let preventEdit = PreventEditDelegate()
    let closeSoftKeyboard = CloseSoftKeyboardDelegate()
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
    struct ImageEntry {
        var image: UIImage
        var path: URL
        var thumbnail: UIImage
        var thumbnailPath: URL
        var isSelected: Bool
        init(image: UIImage, path:URL, thumbnail:UIImage, thumbnailPath:URL){
            self.image = image
            self.path = path
            self.thumbnail = thumbnail
            self.thumbnailPath = thumbnailPath
            self.isSelected = false
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // check if user logged in and save handle
        firebaseManager.isUserlogedIn { (isLogged) in
            if isLogged == false {
                guard let cntrl = self.storyboard?.instantiateViewController(withIdentifier: "FirebaseCredentialsID") as? FirebaseCredentials else {
                    fatalError("Cannot connect a viewController")
                }
                self.present(cntrl, animated: true, completion: nil)
            }

        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // remove listener
        firebaseManager.removeListener()
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        alertManager = AlertManager(target: self.navigationItem)

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
            
            alertManager?.showSpinner(message: "Adding...")
            firebaseManager.addJournalEntry(newEntry, journalRootID: journalRef.entryID) { [weak self] (err) in
                if err != nil {
                    self!.alertManager!.showOkDialogue(title: "Error",
                                                       message: err!.localizedDescription,
                                                       target: self!)
                    
                }
                self?.alertManager?.hideSpinner()
            }

        }
        
        // load default values
        selectedCreationDate = journalRef!.entries[entryIndex!].creationDate
        selectedLocationName = journalRef!.entries[entryIndex!].locationName
        selectedLocationLongitude = journalRef!.entries[entryIndex!].locationLongitute
        selectedLocationLattitude = journalRef!.entries[entryIndex!].locationLattitute
        selectedLocationRegionID = journalRef!.entries[entryIndex!].locationRegionID
        selectedImagesArray.removeAll()

        let fileNames = journalRef!.entries[entryIndex!].imagesFilenames
        let thumbnailsFilename = journalRef!.entries[entryIndex!].thumbnails
        for index in 0 ..< fileNames.count {

            let (img, imageURL) = ImageManager.createImageFromFilename(fileNames[index])
            let (thumbnail, thumbnailURL) = ImageManager.createImageFromFilename(thumbnailsFilename[index])
            
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
        cell.imageView.image = selectedImagesArray[indexPath.row].image
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
            if selectedImagesArray.count < maxImages {
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
            }
        }
    }
    
    //MARK: UIImagePickerControllerDelegate: select and return the image
    
    @objc func imagePickerController(_ picker: UIImagePickerController,
                                     didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        if let img = info[UIImagePickerController.InfoKey.originalImage] as? UIImage,
            let imgURL = info[UIImagePickerController.InfoKey.imageURL] as? URL {
            
            //get small and normal image
            let smallImage = ImageManager.resizeImage(image: img, target: thumbnailSize)
            let normalImage = ImageManager.resizeImage(image: img, target: normalSize)
            
            //get last name of large and small files
            let imgName = imgURL.lastPathComponent
            var imgSmallName = ImageManager.thumbnailPrefix
            imgSmallName.append(contentsOf: imgName)
            
            // get the link to the document dir
            let documentURL = try! FileManager.default.url(for: .documentDirectory,
                                                           in: .userDomainMask,
                                                           appropriateFor: nil,
                                                           create: true)
            
            // convert UIImage into Data
            let imgData = normalImage.jpegData(compressionQuality: 0.5)
            let smallImageData = smallImage.jpegData(compressionQuality: 1.0)
            
            
            // create new URL
            let newImgURL = documentURL.appendingPathComponent(imgName)
            let newSmallImgURL = documentURL.appendingPathComponent(imgSmallName)
            
            // create the file
            try! imgData?.write(to: newImgURL)
            try! smallImageData?.write(to: newSmallImgURL)
            
            
            // create a new entry ref
            let entryRef = ImageEntry(image: normalImage,
                                      path: imgURL,
                                      thumbnail: smallImage,
                                      thumbnailPath: newSmallImgURL)
            
            selectedImagesArray.append(entryRef)
            
            collectionViewRef.reloadData()
        }
        picker.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func deleteJournalEntry(_ sender: Any) {
        
        //return object for del
        let objectForDel = journalRef.entries[entryIndex!]
        
        // remove entry
        if let err = realmManager.removeNestedObject(target: journalRef, object: objectForDel) {
            self.alertManager?.showOkDialogue(title: "Error",
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
                                     lastModifiedDate: Date(),
                                     entryID: nil)

        // Delete an entry
        // Level1 - delete the nested journal entry
        //     Level2 - change the journal root

        // [START Level1]
        alertManager?.showSpinner(message: "Deleting...")
        hasBackgroundWork = true
        firebaseManager.removeNestedJournalEntry(entry: objectForDel, completion: { [weak self] (error) in
            if error != nil {
                self!.alertManager!.showOkDialogue(title: "Error",
                                                   message: error!.localizedDescription,
                                                   target: self!)
                self?.alertManager?.hideSpinner()
                self?.hasBackgroundWork = false
                return
            }
            // [END Level1]
            
            // [START Level2]
            self?.firebaseManager.changeJournalRootFields(
                object: self!.journalRef,
                title: self!.journalRef.title,
                creationDate: self!.journalRef.creationDate,
                lastModifiedDate: Date(),
                numberOFCountries: countries,
                numberOfEntries: entries,
                entryID: self!.journalRef.entryID,
                completion: { [weak self] (error) in
                    if error != nil {
                        self!.alertManager!.showOkDialogue(title: "Error",
                                                           message: error!.localizedDescription,
                                                           target: self!)
                        self?.alertManager?.hideSpinner()
                        self?.hasBackgroundWork = false
                        return
                    }

                    self?.alertManager?.hideSpinner()
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
        if alertManager!.isNotUpdating() {
            saveEntry()
        }
    }

    //MARK: when saveButton has 'Save' title - delete selected images

    @objc func removeSelectedImage(){
        selectedImagesArray.removeAll(where: {( $0.isSelected == true )})
        collectionViewRef.reloadData()
        saveButtonRef.removeTarget(self, action: #selector(removeSelectedImage), for: .touchUpInside)
        saveButtonRef.addTarget(self, action: #selector(saveJournalEntryHandler), for: .touchUpInside)
        saveButtonRef.setTitle("Save", for: .normal)
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
    
    func saveEntry(){
        
        let newObject = JournalEntry(entry: journalRef!.entries[entryIndex!])
        newObject.descriptionText = descriptionText.text
        newObject.creationDate = selectedCreationDate
        newObject.locationLattitute = selectedLocationLattitude!
        newObject.locationLongitute = selectedLocationLongitude!
        newObject.locationName = selectedLocationName ?? ""
        newObject.locationRegionID = selectedLocationRegionID!
        newObject.lastModifiedDate = Date()
        let selectedFileNames = selectedImagesArray.map { $0.path.lastPathComponent }
        let selectedThumbnails = selectedImagesArray.map { $0.thumbnailPath.lastPathComponent }
        
        // add images into journalEntry
        if !realmManager.insertImagesNamesIntoNestedObject(object: newObject,
                                                           imagesNames: selectedFileNames,
                                                           thumbnails: selectedThumbnails ) {
            alertManager?.showOkDialogue(title: "Error",
                                         message: PhotoTimelineError.impossibleInsertImagesIntoNestedObject.localizedDescription,
                                         target: self)
            return
        }

        
        
        
        // replace object at given index
        if !realmManager.replaceNestedObject(rootJournal: journalRef!,
                                         newObject: newObject,
                                         oldObject: journalRef!.entries[entryIndex!]) {
            alertManager?.showOkDialogue(title: "Error",
                                         message: PhotoTimelineError.impossibleReplaceNestedObject.localizedDescription,
                                         target: self)
            return
        }
        
        // get countries and entries
        let (countries, entries) = realmManager.calculateEntriesAndCountries(object: journalRef)
        
        // update journalRoot data
        realmManager.replaceRootData(object: journalRef,
                                     title: nil,
                                     numberOFCountries: countries,
                                     numberOfEntries: entries,
                                     creationDate: nil,
                                     lastModifiedDate: Date(),
                                     entryID: nil)
        
        
        // Level 1 - add data to the firebase
        //     Level 2 - replace the journalRoot and close the viewController
        alertManager?.showSpinner(message: "Updating...")
        hasBackgroundWork = true
        let largeImagesArray = selectedImagesArray.map { $0.image }
        
        // [START Level1] add data to firebase
        firebaseManager.replaceNestedJournalEntry(
            target: journalRef,
            object: newObject,
            largeImages: largeImagesArray,
            completion: { [weak self] (error) in
                if error != nil {
                    self?.alertManager?.showOkDialogue(title: "Error",
                                                       message: error!.localizedDescription,
                                                       target: self!)
                    self?.alertManager?.hideSpinner()
                    return
                }
                // [END Level1]
                
                // [START Level2]
                self?.firebaseManager.changeJournalRootFields (
                    object: self!.journalRef,
                    title: nil,
                    creationDate: nil,
                    lastModifiedDate: Date(),
                    numberOFCountries: countries,
                    numberOfEntries: entries,
                    entryID: nil,
                    completion: { [weak self] (error) in
                        if error != nil {
                            self?.alertManager?.showOkDialogue(title: "Error",
                                                               message: error!.localizedDescription,
                                                               target: self!)
                            self?.alertManager?.hideSpinner()
                            return
                        }
                        self!.navigationController?.popViewController(animated: true)
                        self?.alertManager?.hideSpinner()
                        self?.hasBackgroundWork = false
                        // [END Level2]
                })
        })
        

    }
    
}

