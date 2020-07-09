// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "GADMAdapterVungleInterstitial.h"
#import "GADMAdapterVungleBanner.h"
#import "GADMAdapterVungleConstants.h"
#import "GADMAdapterVungleRouter.h"
#import "GADMAdapterVungleUtils.h"

@interface GADMAdapterVungleInterstitial () <GADMAdapterVungleDelegate>
@end

@implementation GADMAdapterVungleInterstitial {
  /// Connector from the Google Mobile Ads SDK to receive ad configurations.
  __weak id<GADMAdNetworkConnector> _connector;

  /// Vungle banner ad wrapper.
  GADMAdapterVungleBanner *_bannerAd;

  /// Indicates whether an interstitial ad is loaded.
  BOOL _isAdLoaded;
}

+ (nullable Class<GADAdNetworkExtras>)networkExtrasClass {
  return [VungleAdNetworkExtras class];
}

+ (NSString *)adapterVersion {
  return kGADMAdapterVungleVersion;
}

- (instancetype)initWithGADMAdNetworkConnector:(id<GADMAdNetworkConnector>)connector {
  self = [super init];
  if (self) {
    _connector = connector;
  }
  return self;
}

#pragma mark - GAD Ad Network Protocol Banner Methods (MREC)

- (void)getBannerWithSize:(GADAdSize)adSize {
  id<GADMAdNetworkConnector> strongConnector = _connector;
  _bannerAd = [[GADMAdapterVungleBanner alloc] initWithGADMAdNetworkConnector:strongConnector
                                                                      adapter:self];
  [_bannerAd getBannerWithSize:adSize];
}

#pragma mark - GAD Ad Network Protocol Interstitial Methods

- (void)getInterstitial {
  id<GADMAdNetworkConnector> strongConnector = _connector;
  self.desiredPlacement = [GADMAdapterVungleUtils findPlacement:[strongConnector credentials]
                                                  networkExtras:[strongConnector networkExtras]];
  if (!self.desiredPlacement.length) {
    [strongConnector adapter:self
                   didFailAd:GADMAdapterVungleErrorWithCodeAndDescription(
                                 kGADErrorMediationDataError, @"Placement ID not specified.")];
    return;
  }

  VungleSDK *sdk = [VungleSDK sharedSDK];
  if ([[GADMAdapterVungleRouter sharedInstance] hasDelegateForPlacementID:self.desiredPlacement]) {
    NSError *error = GADMAdapterVungleErrorWithCodeAndDescription(
        kGADErrorInvalidRequest,
        @"Only a maximum of one ad per placement can be requested from Vungle.");
    [strongConnector adapter:self didFailAd:error];
    return;
  }

  if ([sdk isInitialized]) {
    [self loadAd];
    return;
  }

  NSString *appID = [GADMAdapterVungleUtils findAppID:[strongConnector credentials]];
  if (!appID) {
    NSError *error = GADMAdapterVungleErrorWithCodeAndDescription(kGADErrorMediationDataError,
                                                                  @"Vungle app ID not specified.");
    [strongConnector adapter:self didFailAd:error];
    return;
  }
  [[GADMAdapterVungleRouter sharedInstance] initWithAppId:appID delegate:self];
}

- (void)stopBeingDelegate {
  if (_bannerAd) {
    [_bannerAd cleanUp];
  } else {
    [[GADMAdapterVungleRouter sharedInstance] removeDelegate:self];
  }

  _connector = nil;
}

- (BOOL)isBannerAnimationOK:(GADMBannerAnimationType)animType {
  return YES;
}

- (void)presentInterstitialFromRootViewController:(UIViewController *)rootViewController {
  id<GADMAdNetworkConnector> strongConnector = _connector;
  if (![[GADMAdapterVungleRouter sharedInstance] playAd:rootViewController
                                               delegate:self
                                                 extras:[strongConnector networkExtras]]) {
    [strongConnector adapterWillPresentInterstitial:self];
    [strongConnector adapterDidDismissInterstitial:self];
    return;
  }
}

#pragma mark - Private methods

- (void)loadAd {
  NSError *error = [[GADMAdapterVungleRouter sharedInstance] loadAd:self.desiredPlacement
                                                       withDelegate:self];
  if (error) {
    [_connector adapter:self didFailAd:error];
  }
}

#pragma mark - VungleRouter delegates

@synthesize desiredPlacement;

- (void)initialized:(BOOL)isSuccess error:(nullable NSError *)error {
  if (!isSuccess) {
    [_connector adapter:self didFailAd:error];
    return;
  }
  [self loadAd];
}

- (void)adAvailable {
  if (_isAdLoaded) {
    // Already invoked an ad load callback.
    return;
  }
  _isAdLoaded = YES;

  [_connector adapterDidReceiveInterstitial:self];
}

- (void)adNotAvailable:(nonnull NSError *)error {
  if (_isAdLoaded) {
    // Already invoked an ad load callback.
    return;
  }

  [_connector adapter:self didFailAd:error];
}

- (void)willShowAd {
  [_connector adapterWillPresentInterstitial:self];
}

- (void)willCloseAd {
  [_connector adapterWillDismissInterstitial:self];
}

- (void)didCloseAd {
  [_connector adapterDidDismissInterstitial:self];
}

- (void)trackClick {
  [_connector adapterDidGetAdClick:self];
}

- (void)willLeaveApplication {
  [_connector adapterWillLeaveApplication:self];
}

- (void)rewardUser {
  // Do nothing.
}

@end
