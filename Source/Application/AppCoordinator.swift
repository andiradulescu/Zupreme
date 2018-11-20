//
//  AppCoordinator.swift
//  Zupreme
//
//  Created by Alexander Cyon on 2018-09-08.
//  Copyright © 2018 Open Zesame. All rights reserved.
//

import UIKit
import RxSwift
import Zesame

final class AppCoordinator: BaseCoordinator<AppCoordinator.Step> {
    enum Step {}

    private unowned let window: UIWindow
    private let useCaseProvider: UseCaseProvider
    private let deepLinkHandler: DeepLinkHandler

    private lazy var walletUseCase = useCaseProvider.makeWalletUseCase()
    private lazy var pincodeUseCase = useCaseProvider.makePincodeUseCase()

    // TODO replace this with navigation stack logic looking at the topmost controller (which I earlier failed to do.)
    private var isCurrentlyPresentingLockScene = false

    init(window: UIWindow, deepLinkHandler: DeepLinkHandler, useCaseProvider: UseCaseProvider) {
        self.window = window
        self.deepLinkHandler = deepLinkHandler
        self.useCaseProvider = useCaseProvider

        let neverUsedNavigationController = UINavigationController()

        super.init(navigationController: neverUsedNavigationController)
        setupDeepLinkNavigationHandling()
    }

    override func start() {
        if walletUseCase.hasConfiguredWallet {
            toMain(lockIfNeeded: true)
        } else {
            toOnboarding()
        }
    }

    override var navigationController: UINavigationController {
        incorrectImplementation("This is a special case, the AppCoordinator should use the `window` and set its rootViewController")
    }
}

// MARK: - Private
private extension AppCoordinator {

    func toOnboarding() {
        let navigationController = UINavigationController()
        window.rootViewController = navigationController

        let onboarding = OnboardingCoordinator(
            navigationController: navigationController,
            useCaseProvider: useCaseProvider
        )

        start(coordinator: onboarding, transition: .replace) { [unowned self] userDid in
            switch userDid {
            case .finishOnboarding: self.toMain()
            }
        }
    }

    func toMain(lockIfNeeded lock: Bool = false) {
        defer { if lock { lockApp() } }
        let navigationController = UINavigationController()
        window.rootViewController = navigationController

        let main = MainCoordinator(
            navigationController: navigationController,
            deepLinkGenerator: DeepLinkGenerator(),
            useCaseProvider: useCaseProvider
        )

        start(coordinator: main, transition: .replace) { [unowned self] userDid in
            switch userDid {
            case .removeWallet: self.toOnboarding()
            }
        }
    }

    func toUnlockAppWithPincodeIfNeeded() {
        guard pincodeUseCase.hasConfiguredPincode, !isCurrentlyPresentingLockScene else { return }
        guard let topMostNavgationController = findTopMostNavigationController() else { incorrectImplementation("should have a navigationController") }
        let viewModel = UnlockAppWithPincodeViewModel(useCase: pincodeUseCase)
        isCurrentlyPresentingLockScene = true
        modallyPresent(
            scene: UnlockAppWithPincode.self,
            viewModel: viewModel,
            navigationController: topMostNavgationController
        ) { [unowned self] userDid, dismissScene in
            switch userDid {
            case .unlockApp:
                self.isCurrentlyPresentingLockScene = false
                dismissScene(true)
            }
        }
    }
}

// MARK: - Lock app with pincode
extension AppCoordinator {
    func appWillResignActive() {
        lockApp()
    }
}

// MARK: - Private Lock app with pincode
private extension AppCoordinator {
    func lockApp() {
        toUnlockAppWithPincodeIfNeeded()
    }

    func findTopMostViewController() -> UIViewController? {
        guard var topController = window.rootViewController else { return nil }
        while let presentedViewController = topController.presentedViewController {
            topController = presentedViewController
        }
        return topController
    }

    func findTopMostNavigationController() -> UINavigationController? {
        guard let topController = findTopMostViewController() else { return nil }
        if let navigationController = topController as? UINavigationController {
            return navigationController
        } else {
            return topController.navigationController
        }
    }

}

// MARK: - DeepLink Handler
extension AppCoordinator {

    /// returns: `true` if the delegate successfully handled the request or `false` if the attempt to open the URL resource failed.
    func handleDeepLink(_ url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        return deepLinkHandler.handle(url: url, options: options)
    }

    func setupDeepLinkNavigationHandling() {
        let deepLinkStepper = Stepper<DeepLink>()
        deepLinkHandler.set(stepper: deepLinkStepper)
        bag <~ deepLinkStepper.navigation.do(onNext: { [unowned self] in
            switch $0 {
            case .send(let transaction): self.toSend(prefilTransaction: transaction)
            }
        }).drive()
    }
}

// MARK: Private DeepLink navigation
private extension AppCoordinator {
    func toSend(prefilTransaction transaction: Transaction) {
        guard let mainCoordinator = anyCoordinatorOf(type: MainCoordinator.self) else { return }
        mainCoordinator.toSendPrefilTransaction(transaction)
    }
}
