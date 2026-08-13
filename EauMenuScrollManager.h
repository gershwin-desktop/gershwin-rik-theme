/*
 * EauMenuScrollManager.h
 *
 * Manages scroll state for overflowing menus, implementing the
 * Mac OS X 10.5 (Leopard) menu scrolling behavior:
 *
 * - When a menu's total height exceeds available screen space, the
 *   menu is resized to fill the screen and items are scrolled via
 *   a virtual viewport with no visible scrollbar.
 * - Scroll wheel / trackpad gestures scroll the item list.
 * - Moving the mouse to the top or bottom edge of the menu triggers
 *   a smooth autoscroll.
 * - The initially-selected item is scrolled into view and centered.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef EAU_MENU_SCROLL_MANAGER_H
#define EAU_MENU_SCROLL_MANAGER_H

#import <AppKit/AppKit.h>

@class NSMenuView;

/**
 * EauMenuScrollManager is associated with an NSMenuView (via
 * objc_setAssociatedObject) when the menu overflows the screen.
 *
 * It holds the scroll offset and provides scrolling operations
 * (scroll wheel delta, edge autoscroll, selection centering).
 */
@interface EauMenuScrollManager : NSObject
{
  NSMenuView   *_menuView;
  CGFloat       _scrollOffset;        // Current scroll offset in points
  CGFloat       _totalContentHeight;  // Sum of all item heights
  CGFloat       _visibleHeight;       // Visible viewport height
  BOOL          _isScrolling;         // YES when overflow mode is active
  NSTimeInterval _lastEdgeScrollTime; // Last time edge scrolling fired (throttle)
}

/**
 * Configure the scroll manager for overflow mode.
 * Call this when the menu is too tall for the screen.
 *
 * @param menuView  The NSMenuView to manage
 * @param totalHeight  The total content height (sum of all items)
 * @param visibleHeight The visible viewport height
 */
- (void) setupWithMenuView: (NSMenuView *)menuView
               totalHeight: (CGFloat)totalHeight
             visibleHeight: (CGFloat)visibleHeight;

/// Current scroll offset, clamped between 0 and maxScrollOffset
@property (nonatomic) CGFloat scrollOffset;

/// Whether overflow mode is active
@property (nonatomic, readonly, getter=isScrolling) BOOL scrolling;

/// Maximum scroll offset (totalContentHeight - visibleHeight)
@property (nonatomic, readonly) CGFloat maxScrollOffset;

/// The visible viewport height
@property (nonatomic, readonly) CGFloat visibleHeight;

/// Update visible height (e.g., on window resize)
- (void) setVisibleHeight: (CGFloat)height;

/// Update the total content height (e.g. when a lazily-populated menu grows
/// after the scroll manager was first created).  Re-clamps scrollOffset.
- (void) setTotalContentHeight: (CGFloat)height;

/// Apply a scroll wheel delta (negative = scroll down, positive = scroll up)
- (void) scrollByDelta: (CGFloat)deltaY;

/// Scroll to bring the item at a given index into the visible viewport,
/// preferably centered.
- (void) scrollItemAtIndexToVisible: (NSInteger)index;

/// Adjust scrollOffset so the item at `index` is fully visible.
/// If `center` is YES, tries to center the item vertically.
- (void) scrollToRevealItemAtIndex: (NSInteger)index centered: (BOOL)center;

/// Convert a rect from content coordinates to viewport coordinates
/// by subtracting scrollOffset.
- (NSRect) viewportRectFromContentRect: (NSRect)contentRect;

/// Convert a point from viewport coordinates to content coordinates
/// by adding scrollOffset.
- (NSPoint) contentPointFromViewportPoint: (NSPoint)viewportPoint;

/// Called from the event loop during tracking. Polls mouse position and
/// scrolls if mouse is near viewport edges. This replaces NSTimer-based
/// edge scrolling which doesn't fire reliably during event tracking loops
/// in NSEventTrackingRunLoopMode on this GNUstep version.
- (void) pollEdgeScroll;

/// Whether edge scrolling is actively happening (within the throttle window).
/// Used as a guard to prevent scroll-into-view conflicts.
- (BOOL) isEdgeScrolling;

// Legacy API — kept for compatibility, now a no-op.
- (void) startEdgeScrolling;
- (void) stopEdgeScrolling;

/// Find the scroll manager associated with a menu view
+ (EauMenuScrollManager *)scrollManagerForMenuView: (NSMenuView *)menuView;
/// Find the scroll manager associated with a window
+ (EauMenuScrollManager *)scrollManagerForWindow: (NSWindow *)window;

/// Check if the menu needs overflow (virtual scrolling), and if so set up
/// the scroll manager and resize the view/window.  Call this from any code
/// path that may run *after* the NSMenuView is attached to its window.
/// Returns YES if overflow mode was activated.
+ (BOOL) setupOverflowForMenuView: (NSMenuView *)menuView;

/// Draw scroll-direction arrow indicators in the given view.
/// Should be called from drawRect: (focus is already locked).
/// Draws small upward/downward triangles at the top/bottom edges of
/// the view when there is content hidden off-screen.
- (void) drawScrollIndicatorsInView: (NSView *)view;

@end

#endif // EAU_MENU_SCROLL_MANAGER_H
