//
//  CertificateKit.h
//
//  MIT License
//
//  Copyright (c) 2017 Ian Spence
//  https://tlsinspector.com/github.html
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

#import <UIKit/UIKit.h>

//! Project version number for CertificateKit.
FOUNDATION_EXPORT double CertificateKitVersionNumber;

//! Project version string for CertificateKit.
FOUNDATION_EXPORT const unsigned char CertificateKitVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <CertificateKit/PublicHeader.h>
#import <CertificateKit/CKCertificate.h>
#import <CertificateKit/CKCertificatePublicKey.h>
#import <CertificateKit/CKCertificateChain.h>
#import <CertificateKit/CKServerInfo.h>
#import <CertificateKit/CKGetter.h>
#import <CertificateKit/CKRevoked.h>
#import <CertificateKit/CKOCSPResponse.h>
#import <CertificateKit/CKCRLResponse.h>
#import <CertificateKit/CKGetterOptions.h>
#import <CertificateKit/CKLogging.h>

/**
 Interface for global CertificateKit methods.
 */
@interface CertificateKit : NSObject

typedef NS_ENUM(NSInteger, CKCertificateError) {
    // Errors relating to connecting to the remote server.
    CKCertificateErrorConnection,
    // Crypto error usually resulting from being run on an unsupported platform.
    CKCertificateErrorCrypto,
    // Invalid parameter information such as hostnames.
    CKCertificateErrorInvalidParameter
};

/**
 *  Get the OpenSSL version used by CKCertificate
 *
 *  @return (NSString *) The OpenSSL version E.G. "1.1.0e"
 */
+ (NSString * _Nonnull) opensslVersion;

/**
 Convience method to get the version of libcurl used by CKServerInfo
 
 @return A string representing the libcurl version
 */
+ (NSString * _Nonnull) libcurlVersion;

/**
 Is a HTTP proxy configured on the device
 */
+ (BOOL) isProxyConfigured;

@end
