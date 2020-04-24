//
//  NSObject+KVO.m
//  KVO
//
//  Created by kegebai on 2018/9/10.
//  Copyright © 2018年 kegebai. All rights reserved.
//

#import "NSObject+KVO.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kClassPrefix = @"KVOClassPrefix_";
static NSString *const kAssociatedObservers = @"KVOAssociatedObservers";

static inline NSArray *ClassMethodNames(Class c) {
    NSMutableArray *names = [NSMutableArray array];
    
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(c, &methodCount);
    
    unsigned int i;
    for (i = 0; i < methodCount; i++) {
        [names addObject:NSStringFromSelector(method_getName(methodList[i]))];
    }
    free(methodList);
    
    return names;
}

static inline void PrintDescription(NSString *name, id obj) {
    NSString *desc = [NSString stringWithFormat:
                      @"%@: %@\n\tNSObject class %s\n\tRuntime class %s\n\tImplementation methods <%@>\n\n",
                      name,
                      obj,
                      class_getName([obj class]),
                      class_getName(object_getClass(obj)),
                      [ClassMethodNames(object_getClass(obj)) componentsJoinedByString:@", "]];
    printf("%s\n", desc.UTF8String);
}

static inline NSString *Getter(NSString *setter) {
    if (setter.length <= 0 || ![setter hasPrefix:@"set"] || ![setter hasSuffix:@":"]) {
        return nil;
    }
    
    // remove `set` at the begining and `:` at the end
    NSString *key = [setter substringWithRange:NSMakeRange(3, setter.length - 4)];
    // lower case the first letter
    NSString *firstLetter = [[key substringToIndex:1] lowercaseString];
    
    key = [key stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:firstLetter];
    
    return key;
}

static inline NSString *Setter(NSString *getter) {
    if (getter.length <= 0) {
        return nil;
    }
    
    // upper case the first letter
    NSString *firstLetter = [[getter substringToIndex:1] uppercaseString];
    NSString *remainingLetters = [getter substringFromIndex:1];
    
    // add `set` at the begining and `:` at the end
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", firstLetter, remainingLetters];
    
    return setter;
}

static inline Class kvo_class(id self, SEL _cmd) {
    return class_getSuperclass(object_getClass(self));
}


@interface Observation : NSObject

@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) ObservingBlock block;

@end

@implementation Observation

- (instancetype)initWithObserver:(NSObject *)observer
                             key:(NSString *)key
                           block:(ObservingBlock)block {
    self = [super init];
    if (self) {
        _observer = observer;
        _key      = [key copy];
        _block    = [block copy];
    }
    return self;
}

@end


static inline void kvo_setter(id self, SEL _cmd, id newValue) {
    NSString *setterName = NSStringFromSelector(_cmd);
    NSString *getterName = Getter(setterName);
    
    if (!getterName) {
        NSString *reason = [NSString stringWithFormat:@"Object %@ does not have setter %@", self, setterName];
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:reason
                                     userInfo:nil];
        return ;
    }
    
    id oldValue = [self valueForKey:getterName];
    
    struct objc_super superclass = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self))
    };
    
    // cast our pointer so the compiler won't complain
    void (*objc_msgSendSuperCasted)(void *, SEL, id) = (void *)objc_msgSendSuper;
    // call super's setter, which is original class's setter method
    objc_msgSendSuperCasted(&superclass, _cmd, newValue);
    // look up observers and call the block
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)kAssociatedObservers);
    
    for (Observation *eachObsevation in observers) {
        if ([eachObsevation.key isEqualToString:getterName]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                eachObsevation.block(self, getterName, oldValue, newValue);
            });
        }
    }
}


@implementation NSObject (KVO)

- (void)kvo_addObserver:(NSObject *)observer
                 forKey:(NSString *)key
             completion:(ObservingBlock)completion {
    
    SEL setterSelector  = NSSelectorFromString(Setter(key));
    Method setterMethod = class_getInstanceMethod([self class], setterSelector);
    
    if (!setterMethod) {
        NSString *reason = [NSString stringWithFormat:@"Object %@ does not have a setter for key %@", self, key];
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:reason
                                     userInfo:nil];
        return ;
    }
    
    Class cls = object_getClass(self);
    NSString *clsName = NSStringFromClass(cls);
    
    // if not an KVO class yet
    if (![clsName hasPrefix:kClassPrefix]) {
        cls = [self kvo_classWithOriginalClassName:clsName];
        object_setClass(self, cls);
    }
    
    // add our kvo setter if this class (not superclasses) doesn't implement the setter?
    if (![self hasSelector:setterSelector]) {
        const char *types = method_getTypeEncoding(setterMethod);
        class_addMethod(cls, setterSelector, (IMP)kvo_setter, types);
    }
    
    Observation *observation = [[Observation alloc] initWithObserver:observer key:key block:completion];
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)(kAssociatedObservers));
    if (!observers) {
        observers = [NSMutableArray array];
        objc_setAssociatedObject(self, (__bridge const void * _Nonnull)(kAssociatedObservers), observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [observers addObject:observation];
}

- (void)kvo_removeObserver:(NSObject *)observer forKey:(NSString *)key {
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)(kAssociatedObservers));
    
    Observation *observation;
    for (Observation *thisObservation in observers) {
        if (thisObservation.observer == observer && [thisObservation.key isEqual:key]) {
            observation = thisObservation;
            break;
        }
    }
    
    [observers removeObject:observation];
}

- (Class)kvo_classWithOriginalClassName:(NSString *)originalClassName {
    NSString *kvoClassName = [kClassPrefix stringByAppendingString:originalClassName];
    Class cls = NSClassFromString(kvoClassName);
    if (cls) {
        return cls;
    }
    
    // class doesn't exist yet, make it
    Class originalClass = object_getClass(self);
    Class kvoClass = objc_allocateClassPair(originalClass, kvoClassName.UTF8String, 0);
    
    // grab class method's signature so we can borrow it
    Method classMethod = class_getInstanceMethod(originalClass, @selector(class));
    const char *types = method_getTypeEncoding(classMethod);
    class_addMethod(kvoClass, @selector(class), (IMP)kvo_class, types);
    
    objc_registerClassPair(kvoClass);
    
    return kvoClass;
}

- (BOOL)hasSelector:(SEL)selector {
    Class cls = object_getClass(self);
    
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(cls, &methodCount);
    
    for (unsigned int i = 0; i < methodCount; i++) {
        SEL thisSelector = method_getName(methodList[i]);
        if (thisSelector == selector) {
            free(methodList);
            return YES;
        }
    }
    free(methodList);
    
    return NO;
}

@end
