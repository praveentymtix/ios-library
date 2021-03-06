/*
 Copyright 2009-2017 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "UARegionEvent+Internal.h"
#import "UAEvent+Internal.h"
#import "UAProximityRegion+Internal.h"
#import "UACircularRegion+Internal.h"
#import "UAGlobal.h"

@implementation UARegionEvent

- (NSString *)eventType {
    return kUARegionEventType;
}

- (UAEventPriority)priority {
    return UAEventPriorityHigh;
}

- (BOOL)isValid {
    if (![UARegionEvent regionEventCharacterCountIsValid:self.regionID]) {
        UA_LERR(@"Region ID must not be greater than %d characters or less than %d character in length.", kUARegionEventMaxCharacters, kUARegionEventMinCharacters);
        return NO;
    }

    if (![UARegionEvent regionEventCharacterCountIsValid:self.source]) {
        UA_LERR(@"Region source must not be greater than %d characters or less than %d character in length.", kUARegionEventMaxCharacters, kUARegionEventMinCharacters);
        return NO;
    }

    if (!(self.boundaryEvent == UABoundaryEventEnter || self.boundaryEvent == UABoundaryEventExit)) {
        UA_LERR(@"Region boundary event must be an enter or exit type.");
        return NO;
    }

    return YES;
}

+ (instancetype)regionEventWithRegionID:(NSString *)regionID source:(NSString *)source boundaryEvent:(UABoundaryEvent)boundaryEvent{
    UARegionEvent *regionEvent = [[self alloc] init];

    regionEvent.source = source;
    regionEvent.regionID = regionID;
    regionEvent.boundaryEvent = boundaryEvent;

    if (![regionEvent isValid]) {
        return nil;
    }

    return regionEvent;
}

- (NSDictionary *)data {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSMutableDictionary *proximityDictionary;
    NSMutableDictionary *circularRegionDictionary;;

    [dictionary setValue:self.source forKey:kUARegionSourceKey];
    [dictionary setValue:self.regionID forKey:kUARegionIDKey];

    if (self.boundaryEvent == UABoundaryEventEnter) {
        [dictionary setValue:kUARegionBoundaryEventEnterValue forKey:kUARegionBoundaryEventKey];
    }
    
    if (self.boundaryEvent == UABoundaryEventExit) {
        [dictionary setValue:kUARegionBoundaryEventExitValue forKey:kUARegionBoundaryEventKey];
    }

    if (self.proximityRegion.isValid) {
        proximityDictionary = [NSMutableDictionary dictionary];

        [proximityDictionary setValue:self.proximityRegion.proximityID forKey:kUAProximityRegionIDKey];
        [proximityDictionary setValue:self.proximityRegion.major forKey:kUAProximityRegionMajorKey];
        [proximityDictionary setValue:self.proximityRegion.minor forKey:kUAProximityRegionMinorKey];

        if (self.proximityRegion.RSSI) {
            [proximityDictionary setValue:self.proximityRegion.RSSI forKey:kUAProximityRegionRSSIKey];
        }

        if (self.proximityRegion.latitude && self.proximityRegion.longitude) {
            [proximityDictionary setValue:[NSString stringWithFormat:@"%.7f", self.proximityRegion.latitude.doubleValue] forKey:kUARegionLatitudeKey];
            [proximityDictionary setValue:[NSString stringWithFormat:@"%.7f", self.proximityRegion.longitude.doubleValue] forKey:kUARegionLongitudeKey];
        }

        [dictionary setValue:proximityDictionary forKey:kUAProximityRegionKey];
    }

    if (self.circularRegion.isValid) {
        circularRegionDictionary = [NSMutableDictionary dictionary];

        [circularRegionDictionary setValue:[NSString stringWithFormat:@"%.1f", self.circularRegion.radius.doubleValue] forKey:kUACircularRegionRadiusKey];
        [circularRegionDictionary setValue:[NSString stringWithFormat:@"%.7f", self.circularRegion.latitude.doubleValue] forKey:kUARegionLatitudeKey];
        [circularRegionDictionary setValue:[NSString stringWithFormat:@"%.7f", self.circularRegion.longitude.doubleValue] forKey:kUARegionLongitudeKey];

        [dictionary setValue:circularRegionDictionary forKey:kUACircularRegionKey];
    }

    return dictionary;
}


- (NSDictionary *)payload {
    /*
     * We are unable to use the event.data for automation because we modify some
     * values to be stringified versions before we store the event to be sent to
     * warp9. Instead we are going to recreate the event data with the unmodified
     * values.
     */

    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSMutableDictionary *proximityDictionary;
    NSMutableDictionary *circularRegionDictionary;;

    [dictionary setValue:self.source forKey:kUARegionSourceKey];
    [dictionary setValue:self.regionID forKey:kUARegionIDKey];

    if (self.boundaryEvent == UABoundaryEventEnter) {
        [dictionary setValue:kUARegionBoundaryEventEnterValue forKey:kUARegionBoundaryEventKey];
    }

    if (self.boundaryEvent == UABoundaryEventExit) {
        [dictionary setValue:kUARegionBoundaryEventExitValue forKey:kUARegionBoundaryEventKey];
    }

    if (self.proximityRegion) {
        proximityDictionary = [NSMutableDictionary dictionary];

        [proximityDictionary setValue:self.proximityRegion.proximityID forKey:kUAProximityRegionIDKey];
        [proximityDictionary setValue:self.proximityRegion.major forKey:kUAProximityRegionMajorKey];
        [proximityDictionary setValue:self.proximityRegion.minor forKey:kUAProximityRegionMinorKey];

        if (self.proximityRegion.RSSI) {
            [proximityDictionary setValue:self.proximityRegion.RSSI forKey:kUAProximityRegionRSSIKey];
        }

        if (self.proximityRegion.latitude && self.proximityRegion.longitude) {
            [proximityDictionary setValue:self.proximityRegion.latitude forKey:kUARegionLatitudeKey];
            [proximityDictionary setValue:self.proximityRegion.longitude forKey:kUARegionLongitudeKey];
        }

        [dictionary setValue:proximityDictionary forKey:kUAProximityRegionKey];
    }

    if (self.circularRegion) {
        circularRegionDictionary = [NSMutableDictionary dictionary];
        [circularRegionDictionary setValue:self.circularRegion.radius forKey:kUACircularRegionRadiusKey];
        [circularRegionDictionary setValue:self.circularRegion.latitude forKey:kUARegionLatitudeKey];
        [circularRegionDictionary setValue:self.circularRegion.longitude forKey:kUARegionLongitudeKey];
        [dictionary setValue:circularRegionDictionary forKey:kUACircularRegionKey];
    }
    
    return dictionary;
}

+ (BOOL)regionEventRSSIIsValid:(NSNumber *)RSSI {
    if (!RSSI || RSSI.doubleValue > kUAProximityRegionMaxRSSI || RSSI.doubleValue < kUAProximityRegionMinRSSI) {
        return NO;
    }

    return YES;
}

+ (BOOL)regionEventRadiusIsValid:(NSNumber *)radius {
    if (!radius || radius.doubleValue > kUACircularRegionMaxRadius || radius.doubleValue < kUACircularRegionMinRadius) {
        return NO;
    }

    return YES;
}

+ (BOOL)regionEventLatitudeIsValid:(NSNumber *)latitude {
    if (!latitude || latitude.doubleValue > kUARegionEventMaxLatitude || latitude.doubleValue < kUARegionEventMinLatitude) {
        return NO;
    }

    return YES;
}

+ (BOOL)regionEventLongitudeIsValid:(NSNumber *)longitude {
    if (!longitude || longitude.doubleValue > kUARegionEventMaxLongitude || longitude.doubleValue < kUARegionEventMinLongitude) {
        return NO;
    }

    return YES;
}

+ (BOOL)regionEventCharacterCountIsValid:(NSString *)string {
    if (!string || string.length > kUARegionEventMaxCharacters || string.length < kUARegionEventMinCharacters) {
        return NO;
    }
    
    return YES;
}

@end
