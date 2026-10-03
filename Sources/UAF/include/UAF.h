#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Apple's Unified Asset Framework is private; everything here is looked up at
// run time and fails closed when a class or selector is missing.
BOOL UAFLoad(void);
NSString *_Nullable UAFAssetType(NSString *assetSet);
// Bytes the asset service reports on disk for a set, or -1 when unknown.
int64_t UAFDownloadedBytes(NSString *assetSet, NSError *_Nullable *_Nullable error);
// The asset service's own inventory: asset sets, installed assets with their
// sizes, and who subscribes to what. Nil when the interface is missing.
NSDictionary *_Nullable UAFInformation(NSError *_Nullable *_Nullable error);
// Asks the asset service to remove the downloaded models of these sets.
// An empty list is refused: the service reads a missing list as "every set".
void UAFResetAssetSets(NSArray<NSString *> *assetSets,
                       void (^completion)(NSError *_Nullable error));

NS_ASSUME_NONNULL_END
