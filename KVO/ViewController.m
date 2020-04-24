//
//  ViewController.m
//  KVO
//
//  Created by kegebai on 2018/9/10.
//  Copyright © 2018年 kegebai. All rights reserved.
//

#import "ViewController.h"
#import "NSObject+KVO.h"

@interface Message : NSObject
@property (nonatomic, copy) NSString *body;
@end

@implementation Message

@end

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UITextField *textField;
@property (nonatomic) Message *message;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.message = [[Message alloc] init];
    
    [self.message kvo_addObserver:self
                           forKey:NSStringFromSelector(@selector(body))
                       completion:^(id observedObj, NSString *observedKey, id oldValue, id newValue) {
                           NSLog(@"%@.%@ is now: %@", observedObj, observedKey, newValue);
                           dispatch_async(dispatch_get_main_queue(), ^{
                               self.textField.text = newValue;
                           });
                       }];
    
    [self changeMessage:nil];
}

- (IBAction)changeMessage:(id)sender {
    
    NSArray *messages = @[
        @"C C++",
        @"Objective C",
        @"Swift",
        @"Hello World!",
        @"Python",
        @"Java",
        @"Java Script",
    ];
    
    NSUInteger index  = arc4random_uniform((u_int32_t)messages.count);
    self.message.body = messages[index];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
