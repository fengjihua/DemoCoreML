//
//  BestImageViewController.swift
//  DemoCoreML
//
//  Created by Michael Feng on 2018/2/1.
//  Copyright © 2018年 FiDensity Inc. All rights reserved.
//

import UIKit

class BestImageViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    var image: UIImage!
    var scale: CGFloat! = 1.0
    
    override func viewDidLoad() {
        print("BestImage viewDidLoad")
        super.viewDidLoad()
        self.setupImageView()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setupImageView() -> Void {
        self.navigationController?.isNavigationBarHidden = false
        self.imageView.image = self.image
        self.imageView.isUserInteractionEnabled = true
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(self.pinchGestureHandler))
        self.imageView.addGestureRecognizer(pinchGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.panGestureHandler))
        self.imageView.addGestureRecognizer(panGesture)
    }
    
    @objc func pinchGestureHandler(recognizer: UIPinchGestureRecognizer) -> Void {
        print(recognizer.scale);
        
        // #warning 放大图片后， 再次缩放的时候，马上回到原先的大小
        //self.imageView.transform = CGAffineTransformMakeScale(pinGest.scale, pinGest.scale);
        
        self.imageView.transform = self.imageView.transform.scaledBy(x: recognizer.scale, y: recognizer.scale)
        self.scale = recognizer.scale
        // 让比例还原，不要累加
        // 解决办法，重新设置scale
        recognizer.scale = 1;
    }
    
    @objc func panGestureHandler(recognizer: UIPanGestureRecognizer) -> Void {
        //拖拽的距离(距离是一个累加)
        let trans = recognizer.translation(in: recognizer.view)
        print(trans)
        
        //设置图片移动
        var center =  self.imageView.center;
        center.x += trans.x * self.scale;
        center.y += trans.y * self.scale;
        self.imageView.center = center;
        
        //清除累加的距离
        recognizer.setTranslation(CGPoint.zero, in: recognizer.view)
    }
}
