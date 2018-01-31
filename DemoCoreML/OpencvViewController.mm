//
//  OpencvViewController.m
//  DemoCoreML
//
//  Created by Michael Feng on 2018/1/27.
//  Copyright © 2018年 FiDensity Inc. All rights reserved.
//

#import <opencv2/opencv.hpp>
#import <opencv2/highgui/ios.h>
#import <opencv2/highgui/cap_ios.h>
#import "OpencvViewController.h"

@interface OpencvViewController ()

@end

@implementation OpencvViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"opencv viewDidLoad");
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (UIImage*)pipeline:(UIImage*)image withVision:(NSInteger)vision withModel:(NSInteger)model {
    NSLog(@"OpenCV Pipline...");
    
    // Process Image Pipline
    cv::Mat img_rgb;
    cv::Mat img_gray;
    cv::Mat img_final;
    
    // iOS Image to OpenCV Matrix
    UIImageToMat(image, img_rgb);
    
    if (vision == 0) {
        img_final = img_rgb;
    }
    
    // 首先将图片由RGBA转成GRAY
    if (vision > 0) {
        cv::cvtColor(img_rgb, img_gray, cv::COLOR_RGB2GRAY);
    }
    
    if (vision == 1) {
        img_final = img_gray;
    }
    
    
    // 反转
    if (vision == 2) {
        img_final = [self bitwiseNot:img_gray];
    }
    
    // Sobel 算子
    if (vision == 3) {
        img_final = [self sobel:img_gray];
    }
    
    // Laplace 算子
    if (vision == 4) {
        img_final = [self laplace:img_gray];
    }
    
    // 将处理后的图片赋值给image，用来显示
//    cv::cvtColor(img_final, img_final, cv::COLOR_GRAY2RGB);
    
    cv::Scalar mean;
    cv::Scalar stddev;
    cv::meanStdDev(img_final, mean, stddev);
//    NSLog(@"%f  %f", mean[0], stddev[0]);
    
    self.blur = int(stddev[0]);
    
    // OpenCV Matrix to iOS Image
    return MatToUIImage(img_final);
}

- (cv::Mat)bitwiseNot:(cv::Mat)img_src {
    cv::Mat img_dst;
    cv::bitwise_not(img_src, img_dst);
    return img_dst;
}

- (cv::Mat)sobel:(cv::Mat)img_src {
    cv::Mat img_dst;
    int ksize = 5;
    cv::Sobel(img_src, img_dst, CV_8U, 1, 1, ksize);
    return img_dst;
}

- (cv::Mat)laplace:(cv::Mat)img_src {
    cv::Mat img_dst;
    int ksize = 5;
    cv::Laplacian(img_src, img_dst, CV_8U, ksize);
    return img_dst;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
