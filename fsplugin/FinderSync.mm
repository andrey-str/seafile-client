//
//  FinderSync.m
//  seafile-client-fsplugin
//
//  Created by Chilledheart on 1/10/15.
//  Copyright (c) 2015 Haiwen. All rights reserved.
//

#import "FinderSync.h"
#import "FinderSyncClient.h"
#include <utility>
#include <map>
#include <algorithm>

#if !__has_feature(objc_arc)
#error this file must be built with ARC support
#endif

@interface FinderSync ()

@property(readwrite, nonatomic, strong) NSTimer *update_watch_set_timer_;
@property(readwrite, nonatomic, strong) NSTimer *update_file_status_timer_;
@end

static const NSArray *const kBadgetIdentifiers = @[
    // According to the document
    // https://developer.apple.com/library/mac/documentation/FinderSync/Reference/FIFinderSyncController_Class/#//apple_ref/occ/instm/FIFinderSyncController/setBadgeIdentifier:forURL:
    // Setting the identifier to an empty string (@"") removes the badge.
    @"", // none
    @"syncing",
    @"error",
    @"ignored",
    @"synced",
];

// Set up images for our badge identifiers. For demonstration purposes,
static void initializeBadgeImages() {
    // Set up images for our badge identifiers. For demonstration purposes,
    // NONE,
    // @""
    // SYNCING,
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage imageNamed:@"status-syncing.icns"]
                     label:NSLocalizedString(@"Syncing", @"Status Syncing")
        forBadgeIdentifier:kBadgetIdentifiers[PathStatus::SYNC_STATUS_SYNCING]];
    // ERROR,
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage imageNamed:@"status-error.icns"]
                     label:NSLocalizedString(@"Error", @"Status Erorr")
        forBadgeIdentifier:kBadgetIdentifiers[PathStatus::SYNC_STATUS_ERROR]];
    // IGNORED
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage imageNamed:@"status-unknown.icns"]
                     label:NSLocalizedString(@"Sync Disabled",
                                             @"Status Disabled")
        forBadgeIdentifier:kBadgetIdentifiers[PathStatus::SYNC_STATUS_IGNORED]];
    // SYNCED,
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage imageNamed:@"status-done.icns"]
                     label:NSLocalizedString(@"Finished", @"Status Finished")
        forBadgeIdentifier:kBadgetIdentifiers[PathStatus::SYNC_STATUS_SYNCED]];
}

inline static void setBadgeIdentifierFor(NSURL *url, PathStatus status) {
    [[FIFinderSyncController defaultController]
        setBadgeIdentifier:kBadgetIdentifiers[status]
                    forURL:url];
}

inline static void setBadgeIdentifierFor(const std::string &path,
                                         PathStatus status) {
    setBadgeIdentifierFor(
        [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]
                   isDirectory:YES],
        status);
}

inline static void setBadgeIdentifierFor(const std::string &worktree,
                                         const std::string &path,
                                         PathStatus status) {
    bool isDirectory = path.back() == '/';
    std::string file = worktree + "/" + path;
    if (isDirectory)
        file.resize(file.size() - 1);
    setBadgeIdentifierFor(
        [NSURL fileURLWithPath:[NSString stringWithUTF8String:file.c_str()]
                   isDirectory:isDirectory],
        status);
}

inline static bool isUnderFolderDirectly(const std::string &dir,
                                         const std::string &path) {
    if (strncmp(dir.data(), path.data(), dir.size()) != 0) {
        return false;
    }
    const char *pos = path.data() + dir.size();
    const char *end = pos + path.size() - (dir.size());
    if (end == pos)
        return true;
    // remove the trailing "/" in path
    if (*(end - 1) == '/')
        --end;
    while (pos != end)
        if (*pos++ == '/')
            return false;
    return true;
}

inline static std::vector<LocalRepo>::const_iterator
findRepo(const std::vector<LocalRepo> &repos, const std::string &repo_id) {
    auto pos = repos.begin();
    for (; pos != repos.end(); ++pos) {
        if (repo_id == pos->repo_id)
            break;
    }
    return pos;
}

inline static std::vector<LocalRepo>::const_iterator
findRepoContainPath(const std::vector<LocalRepo> &repos,
                    const std::string &path) {
    for (auto repo = repos.begin(); repo != repos.end(); ++repo) {
        if (0 == strncmp(repo->worktree.data(), path.data(), repo->worktree.size()))
            return repo;
    }
    return repos.end();
}

static void inline cleanRepoFileStatus(
    const std::string &repo_worktree,
    const std::map<std::string, PathStatus> &repo_status) {

    // clean up root
    setBadgeIdentifierFor(repo_worktree, PathStatus::SYNC_STATUS_NONE);

    // clean up leafs
    for (const auto &file : repo_status) {
        setBadgeIdentifierFor(repo_worktree, file.first,
                              PathStatus::SYNC_STATUS_NONE);
    }
}

static void cleanFileStatus(
    std::map<std::string, std::map<std::string, PathStatus>> *file_status,
    const std::vector<LocalRepo> &watch_set,
    const std::vector<LocalRepo> &new_watch_set) {
    for (const auto &repo : watch_set) {
        bool found = false;
        for (const auto &new_repo : new_watch_set) {
            if (repo == new_repo) {
                found = true;
                break;
            }
        }
        // cleanup old
        if (!found) {
            auto repo_status = file_status->find(repo.repo_id);
            if (repo_status == file_status->end())
                continue;
            cleanRepoFileStatus(repo.worktree, repo_status->second);
            file_status->erase(repo_status);
        }
    }
    for (const auto &new_repo : new_watch_set) {
        bool found = false;
        for (const auto &repo : watch_set) {
            if (repo == new_repo) {
                found = true;
                break;
            }
        }
        // add new
        if (!found)
            (*file_status)[new_repo.repo_id].emplace(
                "/", PathStatus::SYNC_STATUS_NONE);
    }
}

static inline PathStatus convertToPathStatus(LocalRepo::SyncState status) {
    static PathStatus convertor[] = {
        PathStatus::SYNC_STATUS_NONE /* SYNC_STATE_DISABLED = 0 */,
        PathStatus::SYNC_STATUS_SYNCED /* SYNC_STATE_WAITING = 1 */,
        PathStatus::SYNC_STATUS_SYNCED /* SYNC_STATE_INIT = 2*/,
        PathStatus::SYNC_STATUS_SYNCING /* SYNC_STATE_ING = 3*/,
        PathStatus::SYNC_STATUS_SYNCED /* SYNC_STATE_DONE = 4*/,
        PathStatus::SYNC_STATUS_ERROR /* SYNC_STATE_ERROR = 5*/,
        PathStatus::SYNC_STATUS_NONE /* SYNC_STATE_UNKNOWN = 6*/,
        PathStatus::SYNC_STATUS_NONE /* SYNC_STATE_UNSET = 7*/,
    };
    if (status >= LocalRepo::MAX_SYNC_STATE)
        return PathStatus::SYNC_STATUS_NONE;
    return convertor[status];
}

static std::vector<LocalRepo> watched_repos_;
static std::map<std::string, std::map<std::string, PathStatus>> file_status_;
static FinderSyncClient *client_ = nullptr;
static constexpr double kGetWatchSetInterval = 5.0;   // seconds
static constexpr double kGetFileStatusInterval = 2.0; // seconds

@implementation FinderSync

- (instancetype)init {
    self = [super init];

#ifdef NDEBUG
    NSLog(@"%s launched from %@ ; compiled at %s", __PRETTY_FUNCTION__,
          [[NSBundle mainBundle] bundlePath], __DATE__);
#else
    NSLog(@"%s launched from %@ ; compiled at %s %s", __PRETTY_FUNCTION__,
          [[NSBundle mainBundle] bundlePath], __TIME__, __DATE__);
#endif

    // Set up client
    client_ = new FinderSyncClient(self);
    self.update_watch_set_timer_ =
        [NSTimer scheduledTimerWithTimeInterval:kGetWatchSetInterval
                                         target:self
                                       selector:@selector(requestUpdateWatchSet)
                                       userInfo:nil
                                        repeats:YES];

    self.update_file_status_timer_ = [NSTimer
        scheduledTimerWithTimeInterval:kGetFileStatusInterval
                                target:self
                              selector:@selector(requestUpdateFileStatus)
                              userInfo:nil
                               repeats:YES];

    [FIFinderSyncController defaultController].directoryURLs = nil;

    return self;
}

- (void)dealloc {
    delete client_;
    NSLog(@"%s unloaded ; compiled at %s", __PRETTY_FUNCTION__, __TIME__);
}

#pragma mark - Primary Finder Sync protocol methods

- (void)beginObservingDirectoryAtURL:(NSURL *)url {
    std::string dir = url.path.precomposedStringWithCanonicalMapping.UTF8String;

    // find where we have it
    auto repo = findRepoContainPath(watched_repos_, dir);
    if (repo == watched_repos_.end())
        return;

    auto repo_status = file_status_.find(repo->repo_id);
    if (repo_status == file_status_.end())
        return;

    std::string relative_dir;
    // remove the trailing "/" in the header
    if (dir.size() != repo->worktree.size()) {
        relative_dir = std::string(dir.data() + repo->worktree.size() + 1,
                                   dir.size() - repo->worktree.size() - 1);
        relative_dir += "/";
    }

    repo_status->second.emplace(relative_dir, PathStatus::SYNC_STATUS_NONE);
}

- (void)endObservingDirectoryAtURL:(NSURL *)url {
    std::string dir = url.path.precomposedStringWithCanonicalMapping.UTF8String;

    // find where we have it
    auto repo = findRepoContainPath(watched_repos_, dir);
    if (repo == watched_repos_.end())
        return;

    auto repo_status = file_status_.find(repo->repo_id);
    if (repo_status == file_status_.end())
        return;

    std::string relative_dir;
    // remove the trailing "/" in the header
    if (dir.size() != repo->worktree.size()) {
        relative_dir = std::string(dir.data() + repo->worktree.size() + 1,
                                   dir.size() - repo->worktree.size() - 1);
        relative_dir += "/";
    }

    auto &repo_map = repo_status->second;
    decltype(repo_map.begin()) current_file;
    for (auto file = repo_map.begin(); file != repo_map.end();) {
        current_file = file++;
        if (!isUnderFolderDirectly(relative_dir, current_file->first))
            continue;
        repo_map.erase(current_file);
    }
}

- (void)requestBadgeIdentifierForURL:(NSURL *)url {
    std::string file_path = url.path.precomposedStringWithCanonicalMapping.UTF8String;

    // find where we have it
    auto repo = findRepoContainPath(watched_repos_, file_path);
    if (repo == watched_repos_.end())
        return;

    auto repo_status = file_status_.find(repo->repo_id);
    if (repo_status == file_status_.end())
        return;

    std::string path;
    // remove the trailing "/" in the header
    if (file_path.size() != repo->worktree.size()) {
        path = std::string(file_path.data() + repo->worktree.size() + 1,
                           file_path.size() - repo->worktree.size() - 1);
    }
    NSNumber *isDirectory;
    if ([url getResourceValue:&isDirectory
                       forKey:NSURLIsDirectoryKey
                        error:nil] &&
        [isDirectory boolValue]) {
        path += "/";
    }
    repo_status->second.emplace(path, PathStatus::SYNC_STATUS_NONE);

    setBadgeIdentifierFor(repo->worktree, path,
                          PathStatus::SYNC_STATUS_NONE);

    std::string repo_id = repo->repo_id;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
                   ^{
                     client_->doGetFileStatus(repo_id.c_str(), path.c_str());
                   });
}

#pragma mark - Menu and toolbar item support

#if 0
- (NSString *)toolbarItemName {
  return @"Seafile FinderSync";
}

- (NSString *)toolbarItemToolTip {
  return @"Seafile FinderSync: Click the toolbar item for a menu.";
}

- (NSImage *)toolbarItemImage {
  return [NSImage imageNamed:NSImageNameFolder];
}
#endif

- (NSMenu *)menuForMenuKind:(FIMenuKind)whichMenu {
    if (whichMenu != FIMenuKindContextualMenuForItems &&
        whichMenu != FIMenuKindContextualMenuForContainer)
        return nil;
    // Produce a menu for the extension.
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *shareLinkItem =
        [menu addItemWithTitle:NSLocalizedString(@"Get Seafile Share Link",
                                                 @"Get Seafile Share Link")
                        action:@selector(shareLinkAction:)
                 keyEquivalent:@""];
    NSImage *seafileImage = [NSImage imageNamed:@"seafile.icns"];
    [shareLinkItem setImage:seafileImage];

    return menu;
}

- (IBAction)shareLinkAction:(id)sender {
    NSArray *items =
        [[FIFinderSyncController defaultController] selectedItemURLs];
    if (![items count])
        return;
    NSURL *item = items.firstObject;

    std::string fileName = [[item path] UTF8String];

    // do it in another thread
    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
          client_->doSharedLink(fileName.c_str());
        });
}

- (void)requestUpdateWatchSet {
    // do it in another thread
    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
          client_->getWatchSet();
        });
}

- (void)updateWatchSet:(void *)ptr_to_new_watched_repos {
    std::vector<LocalRepo> new_watched_repos;
    if (ptr_to_new_watched_repos)
        new_watched_repos = std::move(
            *static_cast<std::vector<LocalRepo> *>(ptr_to_new_watched_repos));

    cleanFileStatus(&file_status_, watched_repos_, new_watched_repos);

    // overwrite the old watch set
    watched_repos_ = std::move(new_watched_repos);
    for (const auto &repo : watched_repos_) {
        setBadgeIdentifierFor(repo.worktree, convertToPathStatus(repo.status));
    }

    // update FIFinderSyncController's directory URLs
    NSMutableArray *array =
        [NSMutableArray arrayWithCapacity:watched_repos_.size()];
    for (const LocalRepo &repo : watched_repos_) {
        NSString *path = [NSString stringWithUTF8String:repo.worktree.c_str()];
        [array addObject:[NSURL fileURLWithPath:path
                                    isDirectory:YES]];
    }

    [FIFinderSyncController defaultController].directoryURLs =
        [NSSet setWithArray:array];

    // initialize the badge images
    static bool initialized = false;
    if (!initialized) {
        initialized = true;
        initializeBadgeImages();
    }
}

- (void)requestUpdateFileStatus {
    for (const auto &repo_status : file_status_) {
        for (const auto &pair : repo_status.second) {
            if (pair.first.empty() || pair.first == "/")
                continue;
            dispatch_async(
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                  client_->doGetFileStatus(repo_status.first.c_str(),
                                           pair.first.c_str());
                });
        }
    }
}

- (void)updateFileStatus:(const char *)repo_id
                    path:(const char *)path
                  status:(uint32_t)status {
    auto repo = findRepo(watched_repos_, repo_id);
    if (repo == watched_repos_.end())
        return;

    auto repo_status = file_status_.find(repo_id);
    if (repo_status == file_status_.end())
        return;

    auto file = repo_status->second.find(path);
    if (file == repo_status->second.end())
        return;

    // always set up, avoid some bugs
    file->second = static_cast<PathStatus>(status);
    setBadgeIdentifierFor(repo->worktree, file->first,
                          static_cast<PathStatus>(status));
}

@end
