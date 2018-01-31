//
//  OpencvViewController.h
//  DemoCoreML
//
//  Created by Michael Feng on 2018/1/27.
//  Copyright © 2018年 FiDensity Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface OpencvViewController : UIViewController

@property (nonatomic, assign) int blur;
//@property (nonatomic, assign) int fps;

- (UIImage*)pipeline:(UIImage*) image withVision:(NSInteger)vision withModel:(NSInteger)model;

@end
