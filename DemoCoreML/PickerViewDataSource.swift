//
//  PickerViewDataSource.swift
//  DemoCoreML
//
//  Created by Michael Feng on 2018/1/29.
//  Copyright © 2018年 FiDensity Inc. All rights reserved.
//

import UIKit
import Foundation

struct OpenCVDataSource {
    let values = ["RGB", "Gray", "Bitwise Not", "Sobel", "Laplace"]
    
    func title(for index: Int) -> String? {
        guard index < values.count else { return nil }
        return String(values[index])
    }
    
    func value(for index: Int) -> Int? {
        guard index < values.count else { return nil }
        return index
    }
}

struct MLModelDataSource {
    let values = ["MobileNet", "MobileNetV2", "SqueezeNet", "GoogLeNet", "InceptionV3", "Resnet", "YOLO", "SSD"]
    
    func title(for index: Int) -> String? {
        guard index < values.count else { return nil }
        return String(values[index])
    }
    
    func value(for index: Int) -> Int? {
        guard index < values.count else { return nil }
        return index
    }
}

class PickerDataSource: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
    // MARK: - Properties
    
    private let openCVDataSource = OpenCVDataSource()
    private let mlmodelDataSource = MLModelDataSource()
    
    // MARK: - Helpers
    
    /// Find the title for the given feature.
    func title(for row: Int, component: Int) -> String? {
        switch component {
        case 0  :   return openCVDataSource.title(for: row)
        case 1  :   return mlmodelDataSource.title(for: row)
        default :   return ""
        }
    }
    
    /// For the given feature, find the value for the given row.
    func value(for row: Int, component: Int) -> Int {
        let value: Int?
        
        switch component {
        case 0  :   value = openCVDataSource.value(for: row)
        case 1  :   value = mlmodelDataSource.value(for: row)
        default :   value = -1
        }
        
        return value!
    }
    
    // MARK: - UIPickerViewDataSource
    
    /// Hardcoded 2 items in the picker.
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 2
    }
    
    /// Find the count of each column of the picker.
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch component {
        case 0  :   return openCVDataSource.values.count
        case 1  :   return mlmodelDataSource.values.count
        default :   return 0
        }
    }
}
