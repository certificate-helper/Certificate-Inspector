//
//  CKCertificate.m
//
//  MIT License
//
//  Copyright (c) 2016 Ian Spence
//  https://github.com/certificate-helper/CertificateKit
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

#import "CKCertificate.h"
#import "NSDate+ASN1_TIME.h"

#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/err.h>
#include <openssl/bio.h>
#include <openssl/bn.h>
#include <CommonCrypto/CommonCrypto.h>

@interface CKCertificate()

@property (nonatomic) X509 * certificate;
@property (strong, nonatomic, readwrite) NSString * summary;
@property (strong, nonatomic) NSArray<CKAlternateNameObject *> * subjectAltNames;
@property (strong, nonatomic, readwrite) CKCertificatePublicKey * publicKey;
@property (strong, nonatomic, nonnull, readwrite) CKNameObject * subject;
@property (strong, nonatomic, nonnull, readwrite) CKNameObject * issuer;

@property (strong, nonatomic, nullable, readwrite) NSDate * notAfter;
@property (strong, nonatomic, nullable, readwrite) NSDate * notBefore;
@property (nonatomic, readwrite) BOOL isValidDate;
@property (nonatomic, readwrite) BOOL isExpired;
@property (nonatomic, readwrite) BOOL isNotYetValid;

@property (strong, nonatomic, nullable, readwrite) NSURL * ocspURL;
@property (strong, nonatomic, nullable, readwrite) NSArray<NSURL *> * crlDistributionPoints;

@end

@implementation CKCertificate

INSERT_OPENSSL_ERROR_METHOD

+ (CKCertificate * _Nullable) fromSecCertificateRef:(SecCertificateRef _Nonnull)cert {
    NSData * certificateData = (NSData *)CFBridgingRelease(SecCertificateCopyData(cert));
    const unsigned char * bytes = (const unsigned char *)[certificateData bytes];
    // This will leak
    X509 * xcert = d2i_X509(NULL, &bytes, [certificateData length]);
    certificateData = nil;
    return [CKCertificate fromX509:xcert];
}

+ (CKCertificate *) fromX509:(void *)cert {
    CKCertificate * xcert = [CKCertificate new];
    xcert.certificate = (X509 *)cert;
    xcert.publicKey = [CKCertificatePublicKey infoFromCertificate:xcert];
    xcert.subject = [CKNameObject fromSubject:X509_get_subject_name(cert)];
    xcert.issuer = [CKNameObject fromSubject:X509_get_issuer_name(cert)];

    // Keep trying with each subject name for the summary
    if (xcert.subject.commonName.length > 0) {
        xcert.summary = xcert.subject.commonName;
    } else if (xcert.subject.organizationalUnitName.length > 0) {
        xcert.summary = xcert.subject.organizationalUnitName;
    } else if (xcert.subject.organizationName.length > 0) {
        xcert.summary = xcert.subject.organizationName;
    } else if (xcert.subject.emailAddress.length > 0) {
        xcert.summary = xcert.subject.emailAddress;
    } else if (xcert.subject.countryName.length > 0) {
        xcert.summary = xcert.subject.countryName;
    } else if (xcert.subject.stateOrProvinceName.length > 0) {
        xcert.summary = xcert.subject.stateOrProvinceName;
    } else if (xcert.subject.localityName.length > 0) {
        xcert.summary = xcert.subject.localityName;
    } else {
        xcert.summary = @"Untitled Certificate";
    }

    xcert.notAfter = [NSDate fromASN1_TIME:X509_get0_notAfter(cert)];
    xcert.notBefore = [NSDate fromASN1_TIME:X509_get0_notBefore(cert)];

    // Don't consider certs expired/notyetvalid if they're just hours away from the date.
    xcert.isExpired = [xcert.notAfter timeIntervalSinceNow] < 86400;
    xcert.isNotYetValid = [xcert.notBefore timeIntervalSinceNow] > 86400;
    xcert.isValidDate = !xcert.isExpired && !xcert.isNotYetValid;
    
    AUTHORITY_INFO_ACCESS * info = X509_get_ext_d2i(cert, NID_info_access, NULL, NULL);
    int len = sk_ACCESS_DESCRIPTION_num(info);
    for (int i = 0; i < len; i++) {
        // Look for the OCSP entry
        ACCESS_DESCRIPTION * description = sk_ACCESS_DESCRIPTION_value(info, i);
        if (OBJ_obj2nid(description->method) == NID_ad_OCSP) {
            if (description->location->type == GEN_URI) {
                char * ocspurlchar = i2s_ASN1_IA5STRING(NULL, description->location->d.ia5);
                NSString * ocspurlString = [[NSString alloc] initWithUTF8String:ocspurlchar];
                xcert.ocspURL = [NSURL URLWithString:ocspurlString];
            }
        }
    }
    
    CRL_DIST_POINTS * points = X509_get_ext_d2i(cert, NID_crl_distribution_points, NULL, NULL);
    int numberOfPoints = sk_DIST_POINT_num(points);
    if (numberOfPoints < 0) {
        xcert.crlDistributionPoints = @[];
    } else {
        DIST_POINT * point;
        GENERAL_NAMES * fullNames;
        GENERAL_NAME * fullName;
        NSMutableArray<NSURL *> * urls = [NSMutableArray new];
        for (int i = 0; i < numberOfPoints; i ++) {
            point = sk_DIST_POINT_value(points, i);
            fullNames = point->distpoint->name.fullname;
            fullName = sk_GENERAL_NAME_value(fullNames, 0);
            const unsigned char * url = ASN1_STRING_get0_data(fullName->d.uniformResourceIdentifier);
            NSURL * crlURL = [NSURL URLWithString:[NSString stringWithUTF8String:(const char *)url]];
            if (crlURL != nil && [crlURL.absoluteString hasPrefix:@"http"]) {
                [urls addObject:crlURL];
            } else {
                PDebug(@"Unsupported CRL distribution point: %s", url);
            }
        }
        xcert.crlDistributionPoints = urls;
    }

    return xcert;
}

- (NSString *) SHA512Fingerprint {
    return [self digestOfType:CKCertificateFingerprintTypeSHA512];
}

- (NSString *) SHA256Fingerprint {
    return [self digestOfType:CKCertificateFingerprintTypeSHA256];
}

- (NSString *) MD5Fingerprint {
    return [self digestOfType:CKCertificateFingerprintTypeMD5];
}

- (NSString *) SHA1Fingerprint {
    return [self digestOfType:CKCertificateFingerprintTypeSHA1];
}

- (NSString *) digestOfType:(CKCertificateFingerprintType)type {
    const EVP_MD * digest;

    switch (type) {
        case CKCertificateFingerprintTypeSHA512:
            digest = EVP_sha512();
            break;
        case CKCertificateFingerprintTypeSHA256:
            digest = EVP_sha256();
            break;
        case CKCertificateFingerprintTypeSHA1:
            digest = EVP_sha1();
            break;
        case CKCertificateFingerprintTypeMD5:
            digest = EVP_md5();
            break;
    }

    unsigned char fingerprint[EVP_MAX_MD_SIZE];

    unsigned int fingerprint_size = sizeof(fingerprint);
    if (X509_digest(self.certificate, digest, fingerprint, &fingerprint_size) < 0) {
        [self openSSLError];
        PError(@"Unable to generate certificate fingerprint");
        return @"";
    }

    NSMutableString * fingerprintString = [NSMutableString new];

    for (int i = 0; i < fingerprint_size && i < EVP_MAX_MD_SIZE; i++) {
        [fingerprintString appendFormat:@"%02x", fingerprint[i]];
    }

    return fingerprintString;
}

- (BOOL) verifyFingerprint:(NSString *)fingerprint type:(CKCertificateFingerprintType)type {
    NSString * actualFingerprint = [self digestOfType:type];
    NSString * formattedFingerprint = [[fingerprint componentsSeparatedByCharactersInSet:[[NSCharacterSet
                                                                                           alphanumericCharacterSet]
                                                                                          invertedSet]]
                                       componentsJoinedByString:@""];

    return [[actualFingerprint lowercaseString] isEqualToString:[formattedFingerprint lowercaseString]];
}

- (NSString *) serialNumber {
    const ASN1_INTEGER * serial = X509_get0_serialNumber(self.certificate);
    long value = ASN1_INTEGER_get(serial);
    if (value == -1) {
        BIGNUM * bnser = ASN1_INTEGER_to_BN(serial, NULL);
        char * asciiHex = BN_bn2hex(bnser);
        return [NSString stringWithUTF8String:asciiHex];
    } else {
        return [[NSNumber numberWithLong:value] stringValue];
    }
}

- (NSString *) signatureAlgorithm {
    const X509_ALGOR * sigType = X509_get0_tbs_sigalg(self.certificate);
    char buffer[128];
    OBJ_obj2txt(buffer, sizeof(buffer), sigType->algorithm, 0);
    return [NSString stringWithUTF8String:buffer];
}

- (void *) X509Certificate {
    return self.certificate;
}

- (NSData *) publicKeyAsPEM {
    BIO * buffer = BIO_new(BIO_s_mem());
    if (PEM_write_bio_X509(buffer, self.certificate)) {
        BUF_MEM *buffer_pointer;
        BIO_get_mem_ptr(buffer, &buffer_pointer);
        char * pem_bytes = malloc(buffer_pointer->length);
        memcpy(pem_bytes, buffer_pointer->data, buffer_pointer->length-1);

        // Exclude the null terminator from the NSData object
        NSData * pem = [NSData dataWithBytes:pem_bytes length:buffer_pointer->length -1];

        free(pem_bytes);
        free(buffer);

        return pem;
    }

    free(buffer);
    return nil;
}

- (NSArray<CKAlternateNameObject *> *) alternateNames {
    if (self.subjectAltNames) {
        return self.subjectAltNames;
    }

    // This will leak
    GENERAL_NAMES * sans = X509_get_ext_d2i(self.certificate, NID_subject_alt_name, NULL, NULL);
    int numberOfSans = sk_GENERAL_NAME_num(sans);
    if (numberOfSans < 1) {
        return @[];
    }

    NSMutableArray<CKAlternateNameObject *> * names = [NSMutableArray arrayWithCapacity:numberOfSans];
    const GENERAL_NAME * name;

    for (int i = 0; i < numberOfSans; i++) {
        name = sk_GENERAL_NAME_value(sans, i);
        unsigned char * value = NULL;

        CKAlternateNameObject * nameObject = [CKAlternateNameObject new];

        switch (name->type) {
            case GEN_EMAIL:
                nameObject.type = AlternateNameTypeEmail;
                value = name->d.ia5->data;
                break;
            case GEN_DNS:
                nameObject.type = AlternateNameTypeDNS;
                value = name->d.ia5->data;
                break;
            case GEN_URI:
                nameObject.type = AlternateNameTypeURI;
                value = name->d.ia5->data;
                break;
            case GEN_IPADD:
                nameObject.type = AlternateNameTypeIP;

                unsigned char *p;
                char oline[256], htmp[5];
                int i;
                p = name->d.ip->data;
                if (name->d.ip->length == 4) {
                    snprintf(oline, sizeof(oline), "%d.%d.%d.%d", p[0], p[1], p[2], p[3]);
                    value = (unsigned char *)&oline;
                    printf("IP Address: %s\n", value);
                } else if (name->d.ip->length == 16) {
                    oline[0] = 0;
                    for (i = 0; i < 8; i++) {
                        snprintf(htmp, sizeof(htmp), "%X", p[0] << 8 | p[1]);
                        p += 2;
                        // Use of strcat is acceptable here as we use "snprintf" above.
                        strcat(oline, htmp);
                        if (i != 7) {
                            strcat(oline, ":");
                        }
                    }
                    value = (unsigned char *)&oline;
                }
                break;
            default:
                break;
        }
        if (value != NULL) {
            nameObject.value = [NSString stringWithUTF8String:(const char *)value];
            [names addObject:nameObject];
        }
    }

    self.subjectAltNames = names;
    sk_GENERAL_NAME_free(sans);

    return names;
}

- (NSString *) extendedValidationAuthority {
    NSDictionary<NSString *, NSString *> * EV_MAP = @{
        @"1.3.159.1.17.1":               @"Actalis",
        @"1.3.6.1.4.1.34697.2.1":        @"AffirmTrust",
        @"1.3.6.1.4.1.34697.2.2":        @"AffirmTrust",
        @"1.3.6.1.4.1.34697.2.3":        @"AffirmTrust",
        @"1.3.6.1.4.1.34697.2.4":        @"AffirmTrust",
        @"2.16.578.1.26.1.3.3":          @"Buypass",
        @"1.3.6.1.4.1.6449.1.2.1.5.1":   @"Comodo Group",
        @"2.16.840.1.114412.2.1":        @"DigiCert",
        @"2.16.840.1.114412.1.3.0.2":    @"DigiCert",
        @"2.16.792.3.0.4.1.1.4":         @"E-Tugra",
        @"2.16.840.1.114028.10.1.2":     @"Entrust",
        @"1.3.6.1.4.1.14370.1.6":        @"GeoTrust",
        @"1.3.6.1.4.1.4146.1.1":         @"GlobalSign",
        @"2.16.840.1.114413.1.7.23.3":   @"Go Daddy",
        @"1.3.6.1.4.1.14777.6.1.1":      @"Izenpe",
        @"1.3.6.1.4.1.782.1.2.1.8.1":    @"Network Solutions",
        @"1.3.6.1.4.1.22234.2.5.2.3.1":  @"OpenTrust/DocuSign France",
        @"1.3.6.1.4.1.8024.0.2.100.1.2": @"QuoVadis",
        @"1.2.392.200091.100.721.1":     @"SECOM Trust Systems",
        @"2.16.840.1.114414.1.7.23.3":   @"Starfield Technologies",
        @"2.16.756.1.83.21.0":           @"Swisscom",
        @"2.16.756.1.89.1.2.1.1":        @"SwissSign",
        @"2.16.840.1.113733.1.7.48.1":   @"Thawte",
        @"2.16.840.1.114404.1.1.2.4.1":  @"Trustwave",
        @"2.16.840.1.113733.1.7.23.6":   @"Symantec (VeriSign)",
        @"1.3.6.1.4.1.6334.1.100.1":     @"Verizon Business/Cybertrust",
        @"2.16.840.1.114171.500.9":      @"Wells Fargo"
    };

    CERTIFICATEPOLICIES * policies = X509_get_ext_d2i(self.certificate, NID_certificate_policies, NULL, NULL);
    int numberOfPolicies = sk_POLICYINFO_num(policies);

    const POLICYINFO * policy;
    NSString * oid;
    NSString * evAgency;
    for (int i = 0; i < numberOfPolicies; i++) {
        policy = sk_POLICYINFO_value(policies, i);

#define POLICY_BUFF_MAX 32
        char buff[POLICY_BUFF_MAX];
        OBJ_obj2txt(buff, POLICY_BUFF_MAX, policy->policyid, 0);
        oid = [NSString stringWithUTF8String:buff];
        evAgency = [EV_MAP objectForKey:oid];
        if (evAgency) {
            sk_POLICYINFO_free(policies);
            return evAgency;
        }
    }

    sk_POLICYINFO_free(policies);
    return nil;
}

- (BOOL) isCA {
    BASIC_CONSTRAINTS * constraints = X509_get_ext_d2i(self.certificate, NID_basic_constraints, NULL, NULL);
    if (constraints) {
        BOOL ret = constraints->ca > 0;
        BASIC_CONSTRAINTS_free(constraints);
        return ret;
    } else {
        return NO;
    }
}

- (BOOL) extendedValidation {
    return [self extendedValidationAuthority] != nil;
}

- (NSArray<NSString *> *) keyUsage {
    int crit = -1;
    int idx = -1;
    ASN1_BIT_STRING *keyUsage = (ASN1_BIT_STRING *)X509_get_ext_d2i(self.certificate, NID_key_usage, &crit, &idx);
    NSArray<NSString *> * usages = @[@"digitalSignature",
                                     @"nonRepudiation",
                                     @"keyEncipherment",
                                     @"dataEncipherment",
                                     @"keyAgreement",
                                     @"keyCertSign",
                                     @"cRLSign",
                                     @"encipherOnly",
                                     @"decipherOnly"];
    NSMutableArray<NSString *> * values = [NSMutableArray arrayWithCapacity:usages.count];
    for (int i = 0; i < usages.count; i++) {
        if (ASN1_BIT_STRING_get_bit(keyUsage, i)) {
            [values addObject:usages[i]];
        }
    }
    return values;
}

- (NSArray<NSString *> *) extendedKeyUsage {
    int crit = -1;
    int idx = -1;
    ASN1_BIT_STRING *keyUsage = (ASN1_BIT_STRING *)X509_get_ext_d2i(self.certificate, NID_ext_key_usage, &crit, &idx);
    NSArray<NSString *> * usages = @[@"anyExtendedKeyUsage",
                                     @"serverAuth",
                                     @"clientAuth",
                                     @"codeSigning",
                                     @"emailProtection",
                                     @"timeStamping",
                                     @"OCSPSigning"];
    NSMutableArray<NSString *> * values = [NSMutableArray arrayWithCapacity:usages.count];
    for (int i = 0; i < usages.count; i++) {
        if (ASN1_BIT_STRING_get_bit(keyUsage, i)) {
            [values addObject:usages[i]];
        }
    }
    return values;
}

@end
