//
//  CKCertificateChain.m
//
//  LGPLv3
//
//  Copyright (c) 2017 Ian Spence
//  https://tlsinspector.com/github.html
//
//  This library is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This library is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Lesser Public License for more details.
//
//  You should have received a copy of the GNU Lesser Public License
//  along with this library.  If not, see <https://www.gnu.org/licenses/>.

#import "CKCertificateChain.h"

@implementation CKCertificateChain

// Apple does not provide (as far as I am aware) detailed information as to why a certificate chain
// failed evalulation. Therefor we have to made some deductions based off of information we do know.
// Expired (Any)
- (void) determineTrustFailureReason {
    // Expired/Not Valid
    for (CKCertificate * cert in self.certificates) {
        if (cert.isExpired) {
            PWarn(@"Certificate: '%@' expired on: %@", cert.subject.commonNames, cert.notAfter.description);
            self.trusted = CKCertificateChainTrustStatusInvalidDate;
            return;
        } else if (cert.isNotYetValid) {
            PWarn(@"Certificate: '%@' is not yet valid until: %@", cert.subject.commonNames, cert.notBefore.description);
            self.trusted = CKCertificateChainTrustStatusInvalidDate;
            return;
        }
    }

    // Weak RSA
    for (CKCertificate * certificate in self.certificates) {
        if ([certificate.publicKey isWeakRSA]) {
            PWarn(@"Certificate: '%@' has a weak RSA key", certificate.subject.commonNames);
            self.trusted = CKCertificateChainTrustStatusWeakRSAKey;
            return;
        }
    }

    // SHA-1 Leaf
    if ([self.server.signatureAlgorithm hasPrefix:@"sha1"]) {
        PWarn(@"Certificate: '%@' is using SHA-1: '%@'", self.server.subject.commonNames, self.server.signatureAlgorithm);
        self.trusted = CKCertificateChainTrustStatusSHA1Leaf;
        return;
    }

    // SHA-1 Intermediate
    if ([self.intermediateCA.signatureAlgorithm hasPrefix:@"sha1"]) {
        PWarn(@"Certificate: '%@' is using SHA-1: '%@'", self.intermediateCA.subject.commonNames, self.intermediateCA.signatureAlgorithm);
        self.trusted = CKCertificateChainTrustStatusSHA1Intermediate;
        return;
    }

    // Self-Signed
    if (self.certificates.count == 1) {
        PWarn(@"Chain only contains a single certificate");
        self.trusted = CKCertificateChainTrustStatusSelfSigned;
        return;
    }

    // Revoked Leaf
    if (self.server.revoked.isRevoked) {
        PWarn(@"Certificate: '%@' is revoked", self.server.subject.commonNames);
        self.trusted = CKCertificateChainTrustStatusRevokedLeaf;
        return;
    }

    // Revoked Intermedia
    if (self.intermediateCA.revoked.isRevoked) {
        PWarn(@"Certificate: '%@' is revoked", self.intermediateCA.subject.commonNames);
        self.trusted = CKCertificateChainTrustStatusRevokedIntermediate;
        return;
    }

    // Wrong Host
    if (self.server.alternateNames.count == 0) {
        PWarn(@"Certificate: '%@' has no subject alternate names", self.server.subject.commonNames);
        self.trusted = CKCertificateChainTrustStatusWrongHost;
        return;
    }
    BOOL match = NO;
    NSArray<NSString *> * domainComponents = [self.domain.lowercaseString componentsSeparatedByString:@"."];
    for (CKAlternateNameObject * name in self.server.alternateNames) {
        NSArray<NSString *> * nameComponents = [name.value.lowercaseString componentsSeparatedByString:@"."];
        if (domainComponents.count != nameComponents.count) {
            // Invalid
            PWarn(@"Domain components does not match name components");
            continue;
        }

        // SAN Rules:
        //
        // Only the first component of the SAN can be a wildcard
        // Valid: *.google.com
        // Invalid: mail.*.google.com
        //
        // Wildcards only match the same-level of the domain. I.E. *.google.com:
        // Match: mail.google.com
        // Match: calendar.google.com
        // Doesn't match: beta.mail.google.com
        BOOL hasWildcard = [nameComponents[0] isEqualToString:@"*"];
        BOOL validComponents = YES;
        for (int i = 0; i < nameComponents.count; i++) {
            if (i == 0) {
                if (![domainComponents[i] isEqualToString:nameComponents[i]] && !hasWildcard) {
                    validComponents = NO;
                    break;
                }
            } else {
                if (![domainComponents[i] isEqualToString:nameComponents[i]]) {
                    validComponents = NO;
                    break;
                }
            }
        }
        if (validComponents) {
            match = YES;
            break;
        }
    }
    if (!match) {
        PWarn(@"Certificate: '%@' has no subject alternate names that match: '%@'", self.server.subject.commonNames, self.domain);
        self.trusted = CKCertificateChainTrustStatusWrongHost;
        return;
    }

    // Server cert is missing serverAuth EKU
    if (![self.server.extendedKeyUsage containsObject:@"serverAuth"]) {
        PWarn(@"Certificate: '%@' is missing required serverAuth key usage permission", self.server);
        self.trusted = CKCertificateChainTrustStatusLeafMissingRequiredKeyUsage;
        return;
    }

    // Issue Date too long
    if (self.server.validDays > 825) {
        PWarn(@"Certificate: '%@' is valid for too long %lu days", self.server.subject.commonNames, (unsigned long)self.server.validDays);
        self.trusted = CKCertificateChainTrustStatusIssueDateTooLong;
        return;
    }


    // Fallback (We don't know)
    PWarn(@"Unable to determine why certificate: '%@' is untrusted", self.server.subject.commonNames);
    self.trusted = CKCertificateChainTrustStatusUntrusted;

    return;
}

- (NSString *) description {
    NSMutableString * description = [NSMutableString string];
    for (int i = 0; i < self.certificates.count; i++) {
        CKCertificate * certificate = self.certificates[i];
        [description appendFormat:@"Certificate %d:", i];
        [description appendString:[certificate description]];
    }
    return description;
}

@end
