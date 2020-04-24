//
//  NSObject+KVO.h
//  KVO
//
//  Created by kegebai on 2018/9/10.
//  Copyright © 2018年 kegebai. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^ObservingBlock)(id observedObj, NSString *observedKey, id oldValue, id newValue);

@interface NSObject (KVO)

- (void)kvo_addObserver:(NSObject *)observer forKey:(NSString *)key completion:(ObservingBlock)completion;
- (void)kvo_removeObserver:(NSObject *)observer forKey:(NSString *)key;

@end
