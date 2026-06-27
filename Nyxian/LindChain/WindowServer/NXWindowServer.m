/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/ProcEnvironment/Process/PEProcessManager.h>
#import <LindChain/WindowServer/NXKeyboardPortal.h>

@interface NXWindowLayerView : UIView
@end

@implementation NXWindowLayerView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end

@implementation NXWindowServer {
    NXWindow *_activeWindow;
    id_t _activeWindowIdentifier;
    NXWindowLayerView *_windowLayer;
    NXKeyboardPortal *_activePortal;
}

- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene
{
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    static BOOL hasInitialized = NO;
    if(hasInitialized)
    {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"This class may only be initialized once." userInfo:nil];
    }
    
    self = [super initWithWindowScene:windowScene];
    if(self)
    {
        _windows = [[NSMutableDictionary alloc] init];
        _windowOrder = [[NSMutableArray alloc] init];
        _activeWindowIdentifier = (id_t)-1;
        if(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
        {
            [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged:) name:UIDeviceOrientationDidChangeNotification object:nil];
        }
        
        hasInitialized = YES;
    }
    
    _windowLayer = [[NXWindowLayerView alloc] init];
    _windowLayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    _windowLayer.frame = self.bounds;
}

+ (instancetype)sharedWithWindowScene:(UIWindowScene*)windowScene
{
    static NXWindowServer *multitaskManagerSingleton = nil;
    if(windowScene == nil && multitaskManagerSingleton == nil)
    {
        return nil;
    }
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        multitaskManagerSingleton = [[NXWindowServer alloc] initWithWindowScene:windowScene];
    });
    return multitaskManagerSingleton;
}

+ (instancetype)shared
{
    return [self sharedWithWindowScene:nil];
}

- (void)moveWindowToFrontWithNumber:(NSNumber *)number
{
    if(!number || !self.windows[number]) return;

    [self.windowOrder removeObject:number];
    [self.windowOrder insertObject:number atIndex:0];
}

- (void)activateWindowForIdentifier:(id_t)identifier
                           animated:(BOOL)animated
                     withCompletion:(void (^)(void))completion
{
    assert([NSThread isMainThread]);
    
    NXWindow *window = self.windows[@(identifier)];
    if(!window) return;
    
    if(window.view.superview != _windowLayer)
    {
        _activeWindowIdentifier = identifier;
        [self moveWindowToFrontWithNumber:@(identifier)];
        [window.session activateWindow];
        [_windowLayer addSubview:window.view];
        [window openWindow];
        [window focusWindow];
    }
    
    if(completion)
    {
        completion();
    }
}

- (void)deactivateWindowByPullDown:(BOOL)pullDown
                    withIdentifier:(id_t)identifier
                    withCompletion:(void (^)(void))completion
{
    assert([NSThread isMainThread]);
    
    NXWindow *window = self.windows[@(identifier)];
    if(!window || window.view.hidden)
    {
        if(completion)
        {
            completion();
        }
        return;
    }

    [window.view.layer removeAllAnimations];
    
    [UIView animateWithDuration:0.3 animations:^{
        window.view.alpha = 0.0;
    } completion:^(BOOL finished) {
        window.view.hidden = YES;
        window.view.alpha = 1.0;
        window.view.transform = CGAffineTransformIdentity;
        [window.session deactivateWindow];
        if (completion) completion();
    }];
}

- (void)focusWindowForIdentifier:(id_t)identifier
{
    assert([NSThread isMainThread]);
    NXWindow *window = self.windows[@(identifier)];
    if (!window) return;
    [window focusWindow];
}

- (NXWindowSession*)windowSessionForIdentifier:(id_t)identifier
{
    assert([NSThread isMainThread]);
    NXWindow *window = self.windows[@(identifier)];
    if(window != nil)
    {
        return window.session;
    }
    return nil;
}

- (void)unfocusFocusedWindow
{
    assert([NSThread isMainThread]);
    if(_activeWindow != nil)
    {
        [_activeWindow unfocusWindow];
    }
}

- (void)windowsGetOutOfMyWay
{
    if(UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)
    {
        return;
    }
    
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_windowLayer.alpha = 0.25;
    } completion:nil];
}

- (void)windowsGetInMyWay
{
    if(UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)
    {
        return;
    }
    
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_windowLayer.alpha = 1.0;
    } completion:nil];
}

- (void)openWindowWithSession:(NXWindowSession*)session
               withCompletion:(void (^)(BOOL))completion
{
    assert([NSThread isMainThread]);
    
    __block id_t windowIdentifier = (id_t)-1;
    __block BOOL windowOpened = YES;
    
    void (^openAct)(void) = ^{
        /* getting next window identifier */
        static id_t nextWindowIdentifier = 0;
        windowIdentifier = nextWindowIdentifier++;
        
        [session movedWindowToScene:self.windowScene withIdentifier:windowIdentifier];
        
        if(![session openWindow])
        {
            windowOpened = NO;
            return;
        }
        
        NXWindow *window = [[NXWindow alloc] initWithSession:session withDelegate:self];
        window.identifier = windowIdentifier;
        if(window)
        {
            self.windows[@(windowIdentifier)] = window;
            [self windowWantsToFocus:window];
            [self.windowOrder insertObject:@(windowIdentifier) atIndex:0];
            [self activateWindowForIdentifier:windowIdentifier animated:YES withCompletion:nil];
        }
        else
        {
            return;
        }
    };
    
    NXWindow *window = self.windows[@(_activeWindowIdentifier)];
    if(window != nil &&
       _activeWindowIdentifier != window.identifier &&
       [[UIDevice currentDevice] userInterfaceIdiom] != UIUserInterfaceIdiomPad)
    {
        // close first the old one and wait
        [self deactivateWindowByPullDown:YES withIdentifier:_activeWindowIdentifier withCompletion:^{
            openAct();
            if(completion) completion(windowOpened);
        }];
    }
    else
    {
        openAct();
        if(completion) completion(windowOpened);
    }
}

- (void)closeWindowWithIdentifier:(id_t)identifier
                   withCompletion:(void (^)(BOOL))completion
{
    assert([NSThread isMainThread]);
    
    [self unregisterKeyboardPortalWithWindowIdentifier:identifier];
    
    if(_activeWindowIdentifier == identifier)
    {
        _activeWindowIdentifier = (id_t)-1;
    }
    
    NXWindow *window = self.windows[@(identifier)];
    if(window != nil)
    {
        [window closeWindowWithCompletion:^(BOOL closedWindow){
            if(closedWindow)
            {
                [self.windows removeObjectForKey:@(identifier)];
                [self.windowOrder removeObject:@(identifier)];
            }
            
            if(completion) completion(closedWindow);
        }];
    }
    else
    {
        if(completion) completion(NO);
    }
}

- (void)makeKeyAndVisible
{
    [super makeKeyAndVisible];
    
    /* attaching the window layer */
    [self addSubview:_windowLayer];
    [self bringSubviewToFront:_windowLayer];
    [_windowLayer setUserInteractionEnabled:YES];
}

- (BOOL)windowWantsToFocus:(NXWindow *)window
{
    if(_presentationState == NXWindowServerPresentationStateDefault)
    {
        if(_activeWindow != nil &&
           _activeWindow != window)
        {
            [_activeWindow unfocusWindow];
        }
        _activeWindow = window;
        return YES;
    }
    else
    {
        return NO;
    }
}

- (void)windowWantsToClose:(NXWindow *)window
{
    if(_activeWindow == window)
    {
        _activeWindow = nil;
    }
    [window deinit];
    [self.windows removeObjectForKey:@(window.identifier)];
    [self.windowOrder removeObject:@(window.identifier)];
}

- (void)windowWantsToMinimize:(NXWindow *)window
{
    if(_fullScreenWindow == window)
    {
        _fullScreenWindow = nil;
    }
    _activeWindowIdentifier = (id_t)-1;
}

- (void)windowWantsToMaximize:(NXWindow*)window
{
    if(window == nil)
    {
        if(_fullScreenWindow != nil)
        {
            [_fullScreenWindow.view removeFromSuperview];
            [_windowLayer addSubview:_fullScreenWindow.view];
            [_fullScreenWindow.view layoutSubviews];
        }
        
        _fullScreenWindow = nil;
        _presentationState = NXWindowServerPresentationStateDefault;
    }
    else
    {
        if(_fullScreenWindow != nil)
        {
            [_fullScreenWindow.view removeFromSuperview];
            [_windowLayer addSubview:_fullScreenWindow.view];
        }
        
        [window.view removeFromSuperview];
        [self addSubview:window.view];
        [self bringSubviewToFront:window.view];
        [window.view layoutSubviews];
        
        [self windowWantsToFocus:window];
        _fullScreenWindow = window;
        _presentationState = NXWindowServerPresentationStateFullScreen;
    }
}

- (CGRect)window:(NXWindow*)window wantsToChangeToRect:(CGRect)rect
{
    /* getting parameters */
    UIEdgeInsets insets = self.safeAreaInsets;
    CGRect bounds = self.bounds;
    
    /* calculating fullscreen rectangle */
    CGRect allowed = UIEdgeInsetsInsetRect(bounds, insets);
    CGRect boundsInset = allowed;
    allowed.size.height += insets.bottom;
    
    /* checking if maximised */
    if(window.isMaximized)
    {
        if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
        {
            return self.bounds;
        }
        else
        {
            return allowed;
        }
    }
    else
    {
        /* fixing non maximised constraints */
        allowed.origin.x -= (rect.size.width - 50);
        allowed.size.width += ((rect.size.width * 2) - 100);
        allowed.size.height += (rect.size.height - 50);
    }
    
    /* a lot of math */
    if(rect.size.height > boundsInset.size.height)
    {
        rect.size.height = boundsInset.size.height;
    }

    if(rect.origin.x < allowed.origin.x)
    {
        rect.origin.x = allowed.origin.x;
    }
    
    if(CGRectGetMaxX(rect) > CGRectGetMaxX(allowed))
    {
        rect.origin.x = CGRectGetMaxX(allowed) - rect.size.width;
    }
    
    if(rect.origin.y < allowed.origin.y)
    {
        rect.origin.y = allowed.origin.y;
    }
    
    if(CGRectGetMaxY(rect) > CGRectGetMaxY(allowed))
    {
        rect.origin.y = CGRectGetMaxY(allowed) - rect.size.height;
    }
    
    return rect;
}

- (void)orientationChanged:(NSNotification*)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        for(NSNumber *key in self.windows)
        {
            NXWindow *window = self.windows[key];
            if(window != nil)
            {
                [window changeWindowToRect:[self window:window wantsToChangeToRect:window.view.frame] completion:nil];
            }
        }
    });
}

- (UIModalPresentationStyle)styleForTransitionView:(id)view
{
    if(![view isKindOfClass:NSClassFromString(@"UITransitionView")])
    {
        return UIModalPresentationNone;
    }
    
    __strong id delegate = nil;
    if([view respondsToSelector:@selector(delegate)])
    {
        delegate = [view performSelector:@selector(delegate)];
    }
    
    if(delegate == nil)
    {
        return UIModalPresentationNone;
    }
    
    if([delegate isKindOfClass:NSClassFromString(@"_UIFullscreenPresentationController")])
    {
        return UIModalPresentationFullScreen;
    }
    
    return UIModalPresentationNone;
}

- (void)addSubview:(UIView *)view
{
    [super addSubview:view];
    
    if([view isKindOfClass:NSClassFromString(@"UITransitionView")])
    {
        UIModalPresentationStyle presentationStyle = [self styleForTransitionView:view];
        if(presentationStyle == UIModalPresentationFullScreen)
        {
            [super bringSubviewToFront:view];
            [super bringSubviewToFront:_windowLayer];
            if(_fullScreenWindow != nil)
            {
                [super bringSubviewToFront:_fullScreenWindow.view];
            }
        }
        return;
    }
}

- (void)registerKeyboardPortalWithFileDescriptor:(int)fd
                                windowIdentifier:(id_t)wid
{
    assert([NSThread isMainThread]);
    
    if(_activePortal)
    {
        [_activePortal resignFirstResponder];
        [_activePortal removeFromSuperview];
    }
    
    _activePortal = [[NXKeyboardPortal alloc] initWithFrame:CGRectMake(0, 0, 1, 1) fileDescriptor:fd windowIdentifier:wid];
    _activePortal.alpha = 0.01;
    _activePortal.hidden = NO;
    
    [self addSubview:_activePortal];
    [_activePortal becomeFirstResponder];
}

- (void)unregisterKeyboardPortalWithWindowIdentifier:(id_t)wid
{
    assert([NSThread isMainThread]);
    
    if(_activePortal.clientWid == wid)
    {
        [_activePortal resignFirstResponder];
        [_activePortal removeFromSuperview];
        _activePortal = nil;
    }
}

@end
