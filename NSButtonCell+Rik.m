/*
 * NSButtonCell+Rik.m
 * Rik Theme - Button Cell Enhancements
 *
 * This file uses the method swizzling pattern for NSButtonCell to:
 * 1. Intercept common_ret/common_retH images and hide them
 * 2. Automatically set buttons with these images as default buttons
 * 3. Enable pulsing animation for default buttons
 * While 2. and 3. could be done by the application,
 * most applications will not do this, so we handle it here. 
 */

#import "NSCell+Rik.h"
#import "Rik+Button.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface NSButtonCell(RikTheme)
- (NSImage *) RIKimage;
- (NSImage *) RIKalternateImage;
- (BOOL) isProcessingReturnButton;
- (void) setIsProcessingReturnButton:(BOOL)processing;
@end

@implementation Rik(NSButtonCell)
// Override image method using GSTheme method swizzling pattern
- (NSImage *) _overrideNSButtonCellMethod_image
{
  NSButtonCell *xself = (NSButtonCell*) self;
  return [xself RIKimage];
}

// Override alternateImage method using GSTheme method swizzling pattern
- (NSImage *) _overrideNSButtonCellMethod_alternateImage
{
  NSButtonCell *xself = (NSButtonCell*) self;
  return [xself RIKalternateImage];
}
@end

@implementation NSButtonCell(RikTheme)

// Prevent infinite recursion during image processing
static NSMutableSet *processingCells = nil;
static NSMutableSet *defaultButtonSetCells = nil;

+ (void)load
{
  processingCells = [[NSMutableSet alloc] init];
  defaultButtonSetCells = [[NSMutableSet alloc] init];
}

// Helper methods to track processing state
- (BOOL) isProcessingReturnButton
{
  @synchronized(processingCells) {
    return [processingCells containsObject:[NSValue valueWithPointer:self]];
  }
}

- (void) setIsProcessingReturnButton:(BOOL)processing
{
  @synchronized(processingCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:self];
    if (processing) {
      [processingCells addObject:cellPtr];
    } else {
      [processingCells removeObject:cellPtr];
    }
  }
}

// Handle common_ret/common_retH images: hide them and enable button pulsing
- (NSImage *) RIKimage
{
  NSImage *originalImage = [super image];
  if (originalImage)
    {
      NSString *imageName = [originalImage name];
      
      if (imageName && ([imageName isEqualToString:@"common_ret"] || 
                       [imageName isEqualToString:@"common_retH"]))
        {
          // Prevent infinite loops
          if (![self isProcessingReturnButton]) {
            [self setIsProcessingReturnButton:YES];
            [self setIsDefaultButton:@YES];
            [self enablePulsing];
            [self setIsProcessingReturnButton:NO];
          }
          
          return nil; // Hide the image
        }
    }
  
  return originalImage;
}

// Intercept setImage to handle common_ret/common_retH images
- (void) setImage:(NSImage *)image
{
  if (image) {
    NSString *imageName = [image name];
    
    if (imageName && ([imageName isEqualToString:@"common_ret"] || 
                     [imageName isEqualToString:@"common_retH"])) {
      
      // Prevent infinite loops
      if (![self isProcessingReturnButton]) {
        [self setIsProcessingReturnButton:YES];
        [self setIsDefaultButton:@YES];
        [self setIsProcessingReturnButton:NO];
        [self enablePulsing];
      }
      
      return; // Don't set the image
    }
  }
  
  [super setImage:image];
}

// Handle common_ret/common_retH alternate images
- (NSImage *) RIKalternateImage
{
  NSImage *originalImage = nil;

  if ([self respondsToSelector:@selector(alternateImage)]) {
    originalImage = ((NSButtonCell *)self).alternateImage;
  }

  if (originalImage)
    {
      NSString *imageName = [originalImage name];
      
      if (imageName && ([imageName isEqualToString:@"common_ret"] || 
                       [imageName isEqualToString:@"common_retH"]))
        {
          // Prevent infinite loops
          if (![self isProcessingReturnButton]) {
            [self setIsProcessingReturnButton:YES];
            [self setIsDefaultButton:@YES];
            [self enablePulsing];
            [self setIsProcessingReturnButton:NO];
          }
          
          return nil; // Hide the image
        }
    }
  
  return originalImage;
}

// Intercept setAlternateImage to handle common_ret/common_retH images
- (void) RIK_setAlternateImage:(NSImage *)alternateImage
{
  if (alternateImage) {
    NSString *imageName = [alternateImage name];
    
    if (imageName && ([imageName isEqualToString:@"common_ret"] || 
                     [imageName isEqualToString:@"common_retH"])) {
      // Prevent infinite loops
      if (![self isProcessingReturnButton]) {
        [self setIsProcessingReturnButton:YES];
        [self setIsDefaultButton:@YES];
        [self setIsProcessingReturnButton:NO];
        [self enablePulsing];
      }
      
      return; // Don't set the image
    }
  }
  if ([self respondsToSelector:@selector(setAlternateImage:)]) {
    [(NSButtonCell *)self setAlternateImage:alternateImage];
  }
}

// Enable pulsing animation for default buttons
- (void) enablePulsing
{
  [self setIsDefaultButton:@YES];
  [self setPulseProgress:@0];
  [self trySetAsDefaultButtonWithStrategy];
}

// Try multiple strategies to find the window and set default button
- (void) trySetAsDefaultButtonWithStrategy
{
  // Prevent multiple attempts for the same cell
  @synchronized(defaultButtonSetCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:self];
    if ([defaultButtonSetCells containsObject:cellPtr]) {
      return;
    }
  }
  
  // Try immediate window access
  if ([self tryDirectWindowAccess]) {
    return;
  }
  
  // Search all windows for this button cell
  if ([self trySearchAllWindows]) {
    return;
  }
  
  // Schedule delayed attempts
  [self performSelector:@selector(trySetAsDefaultButtonWithStrategy) withObject:nil afterDelay:0.1];
  [self performSelector:@selector(trySetAsDefaultButtonWithStrategy) withObject:nil afterDelay:0.5];
  [self performSelector:@selector(trySetAsDefaultButtonWithStrategy) withObject:nil afterDelay:1.0];
  [self performSelector:@selector(trySetAsDefaultButtonWithStrategy) withObject:nil afterDelay:2.0];
}

// Strategy 1: Try direct window access through controlView
- (BOOL) tryDirectWindowAccess
{
  NSView *controlView = [self controlView];
  NSWindow *window = nil;
  
  if (controlView) {
    window = [controlView window];
    
    if (!window) {
      // Try to find window by traversing the view hierarchy
      NSView *currentView = controlView;
      while (currentView && !window) {
        currentView = [currentView superview];
        if (currentView) {
          window = [currentView window];
        }
      }
    }
    
    if (window) {
      [self markAsDefaultButtonSet];
      [window setDefaultButtonCell:self];
      return YES;
    }
  }
  
  return NO;
}

// Strategy 2: Search all windows for this button cell
- (BOOL) trySearchAllWindows
{
  NSArray *windows = [NSApp windows];
  
  for (NSWindow *candidateWindow in windows) {
    if ([self findButtonWithCellInWindow:candidateWindow]) {
      [self markAsDefaultButtonSet];
      [candidateWindow setDefaultButtonCell:self];
      return YES;
    }
  }
  
  return NO;
}

// Helper to mark this cell as having its default button set
- (void) markAsDefaultButtonSet
{
  @synchronized(defaultButtonSetCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:self];
    [defaultButtonSetCells addObject:cellPtr];
  }
}

// Recursively search for a button that has this cell
- (BOOL) findButtonWithCellInWindow:(NSWindow *)window
{
  return [self findButtonWithCellInView:[window contentView]];
}

- (BOOL) findButtonWithCellInView:(NSView *)view
{
  if ([view isKindOfClass:[NSButton class]]) {
    NSButton *button = (NSButton*)view;
    if ([button cell] == self) {
      return YES;
    }
  }
  
  // Recursively search subviews
  for (NSView *subview in [view subviews]) {
    if ([self findButtonWithCellInView:subview]) {
      return YES;
    }
  }
  
  return NO;
}

@end
