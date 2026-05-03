//
//  SwipeBackGesture.swift
//  Wavify
//
//  Re-enables the interactive swipe-back gesture on screens that hide the
//  default navigation bar back button. iOS disables the gesture by default
//  when `navigationBarBackButtonHidden(true)` is set; making the navigation
//  controller its own gesture-recognizer delegate restores it.
//

import UIKit

extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
