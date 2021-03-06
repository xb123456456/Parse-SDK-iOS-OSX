/**
 * Copyright (c) 2015-present, Parse, LLC.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <OCMock/OCMock.h>

#import <Bolts/BFTask.h>

#import "PFCommandRunning.h"
#import "PFFileManager.h"
#import "PFPaymentTransactionObserver_Private.h"
#import "PFPurchase.h"
#import "PFPurchaseController.h"
#import "PFTestSKPaymentTransaction.h"
#import "PFTestSKProduct.h"
#import "PFUnitTestCase.h"
#import "Parse_Private.h"

@interface PurchaseUnitTests : PFUnitTestCase

@end

@implementation PurchaseUnitTests

///--------------------------------------
#pragma mark - Helpers
///--------------------------------------

- (PFPurchaseController *)mockedPurchaseController {
    id<PFCommandRunning> commandRunner = PFStrictProtocolMock(@protocol(PFCommandRunning));
    PFFileManager *fileManager = PFStrictClassMock([PFFileManager class]);

    PFPurchaseController *purchaseController = PFPartialMock([[PFPurchaseController alloc] initWithCommandRunner:commandRunner
                                                                                                      fileManager:fileManager]);

    SKPaymentQueue *paymentQueue = PFClassMock([SKPaymentQueue class]);
    purchaseController.paymentQueue = paymentQueue;

    return purchaseController;
}

///--------------------------------------
#pragma mark - Tests
///--------------------------------------

- (void)testAddObserver {
    PFPurchaseController *mockedPurchaseController = [self mockedPurchaseController];
    SKPaymentQueue *queue = mockedPurchaseController.paymentQueue;
    [Parse _currentManager].purchaseController = mockedPurchaseController;

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];

    [PFPurchase addObserverForProduct:@"someProduct" block:^(SKPaymentTransaction *transaction) {
        XCTAssertEqualObjects(transaction.payment.productIdentifier, @"someProduct");
        [expectation fulfill];
    }];

    PFPaymentTransactionObserver *transactionObserver = mockedPurchaseController.transactionObserver;
    XCTAssertEqual(transactionObserver.blocks.count, 1);

    PFTestSKProduct *product = [PFTestSKProduct productWithProductIdentifier:@"someProduct"
                                                                       price:nil
                                                                       title:@"The Title"
                                                                 description:@"The description"];

    SKPayment *payment = [SKPayment paymentWithProduct:product];
    OCMStub([queue addPayment:payment]).andDo(^(NSInvocation *invocation) {
        PFTestSKPaymentTransaction *transaction = [PFTestSKPaymentTransaction transactionForPayment:payment
                                                                                          withError:nil
                                                                                            inState:SKPaymentTransactionStatePurchased];
        [transactionObserver paymentQueue:queue updatedTransactions:@[ transaction ]];
    });
    [mockedPurchaseController.paymentQueue addPayment:payment];

    [self waitForTestExpectations];
}

- (void)testBuyProduct {
    PFPurchaseController *mockedPurchaseController = [self mockedPurchaseController];
    [Parse _currentManager].purchaseController = mockedPurchaseController;

    BFTask *mockedTask = [BFTask taskWithResult:nil];
    OCMStub([mockedPurchaseController buyProductAsyncWithIdentifier:@"someProduct"]).andReturn(mockedTask);

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    [PFPurchase buyProduct:@"someProduct" block:^(NSError *error) {
        XCTAssertNil(error);
        [expectation fulfill];
    }];

    [self waitForTestExpectations];
}

- (void)testRestore {
    PFPurchaseController *mockedPurchaseController = [self mockedPurchaseController];
    [Parse _currentManager].purchaseController = mockedPurchaseController;

    SKPaymentQueue *queue = mockedPurchaseController.paymentQueue;

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    OCMStub([queue restoreCompletedTransactions]).andDo(^(NSInvocation *invocation) {
        [expectation fulfill];
    });

    [PFPurchase restore];

    [self waitForTestExpectations];
}

- (void)testDownloadAsset {
    PFPurchaseController *mockedPurchaseController = [self mockedPurchaseController];
    [Parse _currentManager].purchaseController = mockedPurchaseController;

    BFTask *mockedTask = [BFTask taskWithResult:@"SomePath"];

    PFTestSKProduct *testProduct = [PFTestSKProduct productWithProductIdentifier:@"Yarr"
                                                                           price:nil
                                                                           title:@"El Capitan"
                                                                     description:@"Ye Loot"];

    SKPaymentTransaction *transaction = [PFTestSKPaymentTransaction transactionForPayment:[SKPayment paymentWithProduct:testProduct]
                                                                                withError:nil
                                                                                  inState:SKPaymentTransactionStatePurchased];

    OCMStub([mockedPurchaseController downloadAssetAsyncForTransaction:[OCMArg isEqual:transaction]
                                                     withProgressBlock:[OCMArg isNil]
                                                          sessionToken:[OCMArg isNil]]).andReturn(mockedTask);

    OCMStub([mockedPurchaseController downloadAssetAsyncForTransaction:OCMOCK_ANY
                                                     withProgressBlock:OCMOCK_ANY
                                                          sessionToken:OCMOCK_ANY]
            ).andThrow([NSException exceptionWithName:NSInternalInconsistencyException
                                               reason:@"Failed Validation"
                                             userInfo:nil]);

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    [PFPurchase downloadAssetForTransaction:transaction completion:^(NSString *filePath, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(filePath, @"SomePath");

        [expectation fulfill];
    }];

    [self waitForTestExpectations];
}

- (void)testAssetContentPath {
    PFPurchaseController *mockedPurchaseController = [self mockedPurchaseController];
    [Parse _currentManager].purchaseController = mockedPurchaseController;

    NSString *somePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

    OCMStub([mockedPurchaseController assetContentPathForProductWithIdentifier:OCMOCK_ANY
                                                                      fileName:OCMOCK_ANY]).andReturn(somePath);


    XCTAssertNil([PFPurchase assetContentPathForProduct:nil]);

    NSError *error;
    [@"" writeToFile:somePath atomically:YES
            encoding:NSUTF8StringEncoding
               error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil([PFPurchase assetContentPathForProduct:nil]);
}

@end
