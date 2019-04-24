import Foundation
import CoreServices
import WPMediaPicker
import Gutenberg

class GutenbergMediaInserterHelper: NSObject {

    fileprivate let post: AbstractPost

    fileprivate let gutenberg: Gutenberg

    fileprivate let mediaCoordinator = MediaCoordinator.shared

    fileprivate var mediaObserverReceipt: UUID?

    /// Method of selecting media for upload, used for analytics
    ///
    fileprivate var mediaSelectionMethod: MediaSelectionMethod = .none

    var didPickMediaCallback: GutenbergMediaPickerHelperCallback?

    init(post: AbstractPost, gutenberg: Gutenberg) {
        self.post = post
        self.gutenberg = gutenberg
        super.init()
        self.registerMediaObserver()
    }

    deinit {
        self.unregisterMediaObserver()
    }

    func insertFromSiteMediaLibrary(media: Media, callback: @escaping MediaPickerDidPickMediaCallback) {
        callback(media.mediaID?.int32Value, media.remoteURL)
    }

    func insertFromDevice(asset: PHAsset, callback: @escaping MediaPickerDidPickMediaCallback) {
        let media = insert(exportableAsset: asset, source: .deviceLibrary)
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.version = .current
        options.resizeMode = .fast
        let mediaUploadID = media.gutenbergUploadID
        // Getting a quick thumbnail of the asset to display while the image is being exported and uploaded.
        PHImageManager.default().requestImage(for: asset, targetSize: asset.pixelSize(), contentMode: .default, options: options) { (image, info) in
            guard let thumbImage = image, let resizedImage = thumbImage.resizedImage(asset.pixelSize(), interpolationQuality: CGInterpolationQuality.low) else {
                callback(mediaUploadID, nil)
                return
            }
            let filePath = NSTemporaryDirectory() + UUID().uuidString + ".jpg"
            let url = URL(fileURLWithPath: filePath)
            do {
                try resizedImage.writeJPEGToURL(url)
                callback(mediaUploadID, url.absoluteString)
            } catch {
                callback(mediaUploadID, nil)
                return
            }
        }

    }

    func insertFromDevice(url: URL, callback: @escaping MediaPickerDidPickMediaCallback) {
        let media = insert(exportableAsset: url as NSURL, source: .otherApps)
        let mediaUploadID = media.gutenbergUploadID
        callback(mediaUploadID, url.absoluteString)
    }

    func syncUploads() {
        if mediaObserverReceipt != nil {
            registerMediaObserver()
        }
        for media in post.media {
            if media.remoteStatus == .failed {
                gutenberg.mediaUploadUpdate(id: media.gutenbergUploadID, state: .uploading, progress: 0, url: media.absoluteThumbnailLocalURL, serverID: nil)
                gutenberg.mediaUploadUpdate(id: media.gutenbergUploadID, state: .failed, progress: 0, url: nil, serverID: nil)
            }
        }
    }

    func mediaFor(uploadID: Int32) -> Media? {
        for media in post.media {
            if media.gutenbergUploadID == uploadID {
                return media
            }
        }
        return nil
    }

    func isUploadingMedia() -> Bool {
        return mediaCoordinator.isUploadingMedia(for: post)
    }

    func cancelUploadOfAllMedia() {
        mediaCoordinator.cancelUploadOfAllMedia(for: post)
    }

    func cancelUploadOf(media: Media) {
        mediaCoordinator.cancelUploadAndDeleteMedia(media)
        gutenberg.mediaUploadUpdate(id: media.gutenbergUploadID, state: .reset, progress: 0, url: nil, serverID: nil)
    }

    func retryUploadOf(media: Media) {
        mediaCoordinator.retryMedia(media)
    }

    func hasFailedMedia() -> Bool {
        return mediaCoordinator.hasFailedMedia(for: post)
    }

    private func insert(exportableAsset: ExportableAsset, source: MediaSource) -> Media {
        switch exportableAsset.assetMediaType {
        case .image:
            break
        case .video:
            break
        default:
            break
        }

        let info = MediaAnalyticsInfo(origin: .editor(source), selectionMethod: mediaSelectionMethod)
        let media = mediaCoordinator.addMedia(from: exportableAsset, to: self.post, analyticsInfo: info)
        return media
    }

    private func registerMediaObserver() {
        mediaObserverReceipt =  mediaCoordinator.addObserver({ [weak self](media, state) in
            self?.mediaObserver(media: media, state: state)
            }, forMediaFor: post)
    }

    private func unregisterMediaObserver() {
        if let receipt = mediaObserverReceipt {
            mediaCoordinator.removeObserver(withUUID: receipt)
        }
    }

    private func mediaObserver(media: Media, state: MediaCoordinator.MediaState) {
        // Make sure gutenberg is loaded before seding events to it.
        guard gutenberg.isLoaded else {
            return
        }
        let mediaUploadID = media.gutenbergUploadID
        switch state {
        case .processing:
            gutenberg.mediaUploadUpdate(id: mediaUploadID, state: .uploading, progress: 0, url: nil, serverID: nil)
        case .thumbnailReady(let url):
            gutenberg.mediaUploadUpdate(id: mediaUploadID, state: .uploading, progress: 0.20, url: url, serverID: nil)
            break
        case .uploading:
            break
        case .ended:
            guard let urlString = media.remoteURL, let url = URL(string: urlString), let mediaServerID = media.mediaID?.int32Value else {
                break
            }
            switch media.mediaType {
            case .image:
                gutenberg.mediaUploadUpdate(id: mediaUploadID, state: .succeeded, progress: 1, url: url, serverID: mediaServerID)
            case .video:
                fetchRemoteURL(for: media) { [weak self] (result) in
                    guard let strongSelf = self else {
                        return
                    }
                    switch result {
                    case .error:
                        strongSelf.gutenberg.mediaUploadUpdate(id: mediaUploadID, state: .failed, progress: 0, url: nil, serverID: nil)
                    case .success(let value):
                        strongSelf.gutenberg.mediaUploadUpdate(id: mediaUploadID, state: .succeeded, progress: 1, url: value.videoURL, serverID: mediaServerID)
                    }
                }
            default:
                break
            }
        case .failed(let error):
            if error.code == NSURLErrorCancelled {
                gutenberg.mediaUploadUpdate(id: mediaUploadID, state: .reset, progress: 0, url: nil, serverID: nil)
                return
            }
            gutenberg.mediaUploadUpdate(id: mediaUploadID, state: .failed, progress: 0, url: nil, serverID: nil)
        case .progress(let value):
            gutenberg.mediaUploadUpdate(id: mediaUploadID, state: .uploading, progress: Float(value), url: nil, serverID: nil)
        }
    }

    func fetchRemoteURL(for media: Media, completion: @escaping ( Result<(videoURL: URL, posterURL: URL?)> ) -> Void) {
        guard let videoPressID = media.videopressGUID else {
            //the site can be a self-hosted site if there's no videopressGUID
            if let videoURLString = media.remoteURL,
                let videoURL = URL(string: videoURLString) {
                completion(Result.success((videoURL: videoURL, posterURL: nil)))
            } else {
                DDLogError("Unable to find remote video URL for video with upload ID = \(media.uploadID).")
                completion(Result.error(NSError()))
            }
            return
        }
        let mediaService = MediaService(managedObjectContext: ContextManager.sharedInstance().mainContext)
        mediaService.getMediaURL(fromVideoPressID: videoPressID, in: self.post.blog, success: { (videoURLString, posterURLString) in
            guard let videoURL = URL(string: videoURLString) else {
                completion(Result.error(NSError()))
                return
            }
            var posterURL: URL?
            if let validPosterURLString = posterURLString, let url = URL(string: validPosterURLString) {
                posterURL = url
            }
            completion(Result.success((videoURL: videoURL, posterURL: posterURL)))
        }, failure: { (error) in
            DDLogError("Unable to find information for VideoPress video with ID = \(videoPressID). Details: \(error.localizedDescription)")
            completion(Result.error(error))
        })
    }
}

extension Media {
    var gutenbergUploadID: Int32 {
        return Int32(truncatingIfNeeded: objectID.uriRepresentation().absoluteString.hash)
    }
}
