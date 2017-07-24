/*
See LICENSE folder for this sample’s licensing information.

Abstract:
GKComponent subclass that defines behaviors of the main character.
*/

#import "AAPLPlayerComponent.h"

@implementation AAPLPlayerComponent

- (void)updateWithDeltaTime:(NSTimeInterval)seconds
{
    [self positionAgentFromNode];
    [super updateWithDeltaTime:seconds];
}


@end
