//! Private, explicitly indexed motion cache. No access-time dependency or image-cache traversal.
use super::{AnimatedArtworkAsset, AnimatedArtworkError, StoredMotion};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};
use tokio::fs;
use tokio::io::AsyncReadExt;

pub(super) const BUDGET: u64 = 150 * 1024 * 1024;
pub(super) const MAX_FILE: u64 = 128 * 1024 * 1024;
// Leave room for the bounded metadata/index file inside the 150 MiB on-disk ceiling.
const INDEX_ALLOWANCE: u64 = 2 * 1024 * 1024;
const MAX_INDEX: u64 = 1024 * 1024;
const FILE_BUDGET: u64 = BUDGET - INDEX_ALLOWANCE;
const NEGATIVE_SCHEMA: u32 = 2;
const INDEX: &str = "sbam-index-v1.json";
#[derive(Default, Serialize, Deserialize)]
struct Index {
    version: u32,
    assets: HashMap<String, Entry>,
    metadata: HashMap<String, Metadata>,
}
#[derive(Clone, Serialize, Deserialize)]
struct Entry {
    asset: AnimatedArtworkAsset,
    file: String,
    last_used: u64,
}
#[derive(Clone, Serialize, Deserialize)]
pub(super) struct Metadata {
    pub expires: u64,
    #[serde(default)]
    pub negative_schema: u32,
    pub motion: Option<StoredMotion>,
}
pub(super) type Leases = Arc<Mutex<HashMap<String, HashSet<String>>>>;
pub(super) fn release(leases: &Leases, request: &str) {
    leases
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .retain(|_, ids| {
            ids.remove(request);
            !ids.is_empty()
        });
}
#[cfg(test)]
pub(super) struct IoPause {
    pub phase: &'static str,
    pub reached: tokio::sync::oneshot::Sender<()>,
    pub resume: tokio::sync::oneshot::Receiver<()>,
}
pub(super) struct Cache {
    root: PathBuf,
    index: Index,
    reservations: HashMap<String, u64>,
    pub leases: Leases,
    #[cfg(test)]
    pub io_pause: Option<IoPause>,
}
pub(super) fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
fn owned(name: &str) -> bool {
    name.starts_with("sbam-")
        && (name.ends_with(".mp4") || name.ends_with(".part"))
        && !name.contains('/')
        && !name.contains('\\')
}
impl Cache {
    #[cfg(test)]
    pub async fn pause_io(&mut self, phase: &str) {
        if self
            .io_pause
            .as_ref()
            .is_some_and(|pause| pause.phase == phase)
        {
            let pause = self.io_pause.take().unwrap();
            let _ = pause.reached.send(());
            let _ = pause.resume.await;
        }
    }
    pub async fn open(root: &str) -> Result<Self, AnimatedArtworkError> {
        let root = PathBuf::from(root);
        fs::create_dir_all(&root).await?;
        let mut bytes = Vec::new();
        let read = match fs::File::open(root.join(INDEX)).await {
            Ok(file) => file.take(MAX_INDEX + 1).read_to_end(&mut bytes).await,
            Err(e) => Err(e),
        };
        let index = match read {
            Ok(_) if bytes.len() as u64 <= MAX_INDEX => serde_json::from_slice::<Index>(&bytes)
                .ok()
                .filter(|i| i.version == 1)
                .unwrap_or_default(),
            _ => Index::default(),
        };
        let mut cache = Self {
            root,
            index,
            reservations: HashMap::new(),
            leases: Arc::new(Mutex::new(HashMap::new())),
            #[cfg(test)]
            io_pause: None,
        };
        // A previous process cannot retain a lease. Recover indexed bytes and delete only our orphans.
        let mut valid = HashMap::new();
        for (id, entry) in &cache.index.assets {
            if owned(&entry.file) && entry.file.ends_with(".mp4") {
                if let Ok(metadata) = fs::symlink_metadata(cache.root.join(&entry.file)).await {
                    if metadata.is_file() && metadata.len() == entry.asset.size_bytes {
                        valid.insert(id.clone(), entry.clone());
                    }
                }
            }
        }
        cache.index.assets = valid;
        let tracked: HashSet<_> = cache
            .index
            .assets
            .values()
            .map(|e| e.file.clone())
            .collect();
        let mut files = fs::read_dir(&cache.root).await?;
        while let Some(entry) = files.next_entry().await? {
            let name = entry.file_name().to_string_lossy().into_owned();
            if owned(&name) && !tracked.contains(&name) {
                fs::remove_file(entry.path()).await?;
            }
        }
        cache.prune(0).await?;
        cache.save().await?;
        Ok(cache)
    }
    async fn save(&mut self) -> Result<(), AnimatedArtworkError> {
        self.index.version = 1;
        let bytes = loop {
            let bytes =
                serde_json::to_vec(&self.index).map_err(|_| AnimatedArtworkError::InvalidMedia)?;
            if bytes.len() as u64 <= MAX_INDEX {
                break bytes;
            }
            let Some(oldest) = self
                .index
                .metadata
                .iter()
                .min_by_key(|(_, m)| m.expires)
                .map(|(k, _)| k.clone())
            else {
                return Err(AnimatedArtworkError::Capacity);
            };
            self.index.metadata.remove(&oldest);
        };
        let temp = self.root.join("sbam-index-v1.tmp");
        fs::write(&temp, bytes).await?;
        // Tokio rename uses atomic replacement (MoveFileExW on Windows).
        fs::rename(temp, self.root.join(INDEX)).await?;
        Ok(())
    }
    pub fn stored_metadata(&self, key: &str) -> Option<Metadata> {
        self.index.metadata.get(key).cloned()
    }
    pub fn metadata(&self, key: &str) -> Option<Metadata> {
        self.index
            .metadata
            .get(key)
            .filter(|m| {
                m.expires > now() && (m.motion.is_some() || m.negative_schema == NEGATIVE_SCHEMA)
            })
            .cloned()
    }
    pub async fn set_metadata(
        &mut self,
        key: String,
        motion: Option<StoredMotion>,
    ) -> Result<(), AnimatedArtworkError> {
        let assets = &self.index.assets;
        self.index.metadata.retain(|_, m| {
            m.expires > now()
                || m.motion.as_ref().is_some_and(|motion| {
                    motion
                        .variants
                        .iter()
                        .any(|v| assets.contains_key(&super::asset_key(&motion.collection_id, v)))
                })
        });
        if self.index.metadata.len() >= 512 {
            if let Some(oldest) = self
                .index
                .metadata
                .iter()
                .min_by_key(|(_, m)| m.expires)
                .map(|(k, _)| k.clone())
            {
                self.index.metadata.remove(&oldest);
            }
        }
        let ttl = if motion.is_some() {
            30 * 86400
        } else {
            7 * 86400
        };
        self.index.metadata.insert(
            key,
            Metadata {
                expires: now() + ttl,
                negative_schema: NEGATIVE_SCHEMA,
                motion,
            },
        );
        self.save().await
    }
    pub async fn lookup(
        &mut self,
        id: &str,
    ) -> Result<Option<AnimatedArtworkAsset>, AnimatedArtworkError> {
        if let Some(entry) = self.index.assets.get_mut(id) {
            let path = self.root.join(&entry.file);
            if fs::metadata(&path)
                .await
                .map(|m| m.len() == entry.asset.size_bytes)
                .unwrap_or(false)
            {
                entry.last_used = now();
                let mut asset = entry.asset.clone();
                asset.local_path = path.to_string_lossy().into_owned();
                self.save().await?;
                return Ok(Some(asset));
            }
        }
        self.index.assets.remove(id);
        Ok(None)
    }
    pub fn lease(&mut self, id: &str, request: String) {
        self.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .entry(id.to_owned())
            .or_default()
            .insert(request);
    }
    #[cfg(test)]
    pub fn release(&mut self, request: &str) {
        release(&self.leases, request);
    }
    pub fn bytes(&self) -> u64 {
        self.index
            .assets
            .values()
            .map(|e| e.asset.size_bytes)
            .sum::<u64>()
            + self.reservations.values().sum::<u64>()
    }
    /// Settings report actual retained bytes; reservation estimates exist only for admission control.
    pub async fn disk_bytes(&self) -> Result<u64, AnimatedArtworkError> {
        let mut total = 0u64;
        for entry in self.index.assets.values() {
            match fs::metadata(self.root.join(&entry.file)).await {
                Ok(metadata) => total = total.saturating_add(metadata.len()),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Err(e) => return Err(e.into()),
            }
        }
        for id in self.reservations.keys() {
            match fs::metadata(self.root.join(format!("sbam-{id}.part"))).await {
                Ok(metadata) => total = total.saturating_add(metadata.len()),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Err(e) => return Err(e.into()),
            }
        }
        Ok(total)
    }
    async fn prune(&mut self, additional: u64) -> Result<(), AnimatedArtworkError> {
        let mut entries: Vec<_> = self
            .index
            .assets
            .iter()
            .filter(|(id, _)| {
                !self
                    .leases
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .contains_key(*id)
            })
            .map(|(id, e)| (id.clone(), e.last_used))
            .collect();
        entries.sort_by_key(|(_, used)| *used);
        for (id, _) in entries {
            if self.bytes().saturating_add(additional) <= FILE_BUDGET {
                break;
            }
            if let Some(entry) = self.index.assets.get(&id) {
                match fs::remove_file(self.root.join(&entry.file)).await {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(_) => continue,
                }
            }
            self.index.assets.remove(&id);
        }
        if self.bytes().saturating_add(additional) > FILE_BUDGET {
            return Err(AnimatedArtworkError::Capacity);
        }
        Ok(())
    }
    pub async fn reserve(&mut self, id: &str, bytes: u64) -> Result<PathBuf, AnimatedArtworkError> {
        if bytes > MAX_FILE {
            return Err(AnimatedArtworkError::Capacity);
        }
        self.prune(bytes).await?;
        self.reservations.insert(id.to_owned(), bytes);
        self.save().await?;
        Ok(self.root.join(format!("sbam-{id}.part")))
    }
    pub async fn abort(&mut self, id: &str) {
        match fs::remove_file(self.root.join(format!("sbam-{id}.part"))).await {
            Ok(()) => {
                self.reservations.remove(id);
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                self.reservations.remove(id);
            }
            Err(_) => {} // Keep failed-delete bytes reserved until a later cleanup can remove them.
        }
    }
    pub async fn commit(
        &mut self,
        mut asset: AnimatedArtworkAsset,
    ) -> Result<AnimatedArtworkAsset, AnimatedArtworkError> {
        let id = &asset.asset_id;
        let reserved = self.reservations.get(id).copied().unwrap_or(0);
        if asset.size_bytes > reserved {
            return Err(AnimatedArtworkError::Capacity);
        }
        let file = format!("sbam-{id}.mp4");
        fs::rename(
            self.root.join(format!("sbam-{id}.part")),
            self.root.join(&file),
        )
        .await?;
        #[cfg(test)]
        self.pause_io("renamed").await;
        asset.local_path = self.root.join(&file).to_string_lossy().into_owned();
        self.reservations.remove(id);
        self.index.assets.insert(
            id.clone(),
            Entry {
                asset: asset.clone(),
                file,
                last_used: now(),
            },
        );
        self.save().await?;
        Ok(asset)
    }
    pub async fn clear(&mut self) -> Result<u64, AnimatedArtworkError> {
        let entries: Vec<_> = self
            .index
            .assets
            .iter()
            .filter(|(id, _)| {
                !self
                    .leases
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .contains_key(*id)
            })
            .map(|(id, e)| (id.clone(), e.file.clone()))
            .collect();
        for (id, file) in entries {
            match fs::remove_file(self.root.join(file)).await {
                Ok(()) => {
                    self.index.assets.remove(&id);
                }
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                    self.index.assets.remove(&id);
                }
                Err(_) => {}
            }
        }
        let reservations: Vec<_> = self.reservations.keys().cloned().collect();
        for id in reservations {
            self.abort(&id).await;
        }
        self.save().await?;
        self.disk_bytes().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn root() -> String {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        std::env::temp_dir()
            .join(format!(
                "sideb-motion-test-{}-{}-{}",
                std::process::id(),
                now_nanos(),
                NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
            ))
            .to_string_lossy()
            .into_owned()
    }
    fn now_nanos() -> u128 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    }
    #[tokio::test]
    async fn clear_preserves_leased_and_foreign_files() {
        let root = root();
        let mut cache = Cache::open(&root).await.unwrap();
        fs::write(Path::new(&root).join("foreign.mp4"), b"keep")
            .await
            .unwrap();
        let path = cache.reserve("abc", 4).await.unwrap();
        fs::write(path, b"test").await.unwrap();
        cache
            .commit(AnimatedArtworkAsset {
                asset_id: "abc".into(),
                local_path: String::new(),
                codec: "h264".into(),
                width: 1080,
                height: 1080,
                frame_rate: 60.,
                size_bytes: 4,
            })
            .await
            .unwrap();
        cache.lease("abc", "consumer".into());
        assert_eq!(cache.clear().await.unwrap(), 4);
        cache.release("consumer");
        assert_eq!(cache.clear().await.unwrap(), 0);
        assert!(Path::new(&root).join("foreign.mp4").exists());
        let _ = fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn reservations_count_and_reject_overcommit() {
        let root = root();
        let mut c = Cache::open(&root).await.unwrap();
        c.reserve("a", MAX_FILE).await.unwrap();
        assert!(c.reserve("b", MAX_FILE).await.is_err());
        assert_eq!(c.bytes(), MAX_FILE);
        c.abort("a").await;
        assert_eq!(c.bytes(), 0);
        let _ = fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn recovery_removes_owned_orphans_only() {
        let root = root();
        fs::create_dir_all(&root).await.unwrap();
        fs::write(Path::new(&root).join("sbam-orphan.part"), b"partial")
            .await
            .unwrap();
        fs::write(Path::new(&root).join("unrelated.part"), b"keep")
            .await
            .unwrap();
        let c = Cache::open(&root).await.unwrap();
        assert_eq!(c.bytes(), 0);
        assert!(!Path::new(&root).join("sbam-orphan.part").exists());
        assert!(Path::new(&root).join("unrelated.part").exists());
        let _ = fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn explicit_lru_prunes_oldest_and_respects_lease() {
        let root = root();
        let mut c = Cache::open(&root).await.unwrap();
        for (id, last_used) in [("old", 1), ("new", 2), ("leased", 0)] {
            let path = c.reserve(id, 4).await.unwrap();
            fs::write(path, b"test").await.unwrap();
            c.commit(AnimatedArtworkAsset {
                asset_id: id.into(),
                local_path: String::new(),
                codec: "h264".into(),
                width: 1080,
                height: 1080,
                frame_rate: 60.,
                size_bytes: 4,
            })
            .await
            .unwrap();
            c.index.assets.get_mut(id).unwrap().last_used = last_used;
        }
        c.lease("leased", "consumer".into());
        c.prune(FILE_BUDGET - 8).await.unwrap();
        assert!(!c.index.assets.contains_key("old"));
        assert!(c.index.assets.contains_key("new"));
        assert!(c.index.assets.contains_key("leased"));
        let _ = fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn metadata_ttls_and_clear_preserve_verdicts() {
        let root = root();
        let mut c = Cache::open(&root).await.unwrap();
        c.set_metadata("absent".into(), None).await.unwrap();
        c.set_metadata(
            "present".into(),
            Some(StoredMotion {
                collection_id: "1".into(),
                variants: vec![],
            }),
        )
        .await
        .unwrap();
        let absent = c.metadata("absent").unwrap();
        let present = c.metadata("present").unwrap();
        assert!(absent.expires >= now() + 7 * 86400 - 1);
        assert!(present.expires >= now() + 30 * 86400 - 1);
        c.clear().await.unwrap();
        assert!(c.metadata("absent").is_some());
        assert!(c.metadata("present").is_some());
        let _ = fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn externally_removed_video_does_not_leave_phantom_bytes_after_clear() {
        let root = root();
        let mut c = Cache::open(&root).await.unwrap();
        fs::write(c.reserve("gone", 4).await.unwrap(), b"test")
            .await
            .unwrap();
        let asset = c
            .commit(AnimatedArtworkAsset {
                asset_id: "gone".into(),
                local_path: String::new(),
                codec: "h264".into(),
                width: 1080,
                height: 1080,
                frame_rate: 60.,
                size_bytes: 4,
            })
            .await
            .unwrap();
        fs::remove_file(&asset.local_path).await.unwrap();
        assert_eq!(c.disk_bytes().await.unwrap(), 0);
        assert_eq!(c.clear().await.unwrap(), 0);
        assert!(c.index.assets.is_empty());
        let _ = fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn oversized_index_is_discarded_without_loading_unbounded_json() {
        let root = root();
        fs::create_dir_all(&root).await.unwrap();
        fs::write(
            Path::new(&root).join(INDEX),
            vec![b' '; MAX_INDEX as usize + 1],
        )
        .await
        .unwrap();
        let c = Cache::open(&root).await.unwrap();
        assert_eq!(c.bytes(), 0);
        assert!(
            fs::metadata(Path::new(&root).join(INDEX))
                .await
                .unwrap()
                .len()
                <= MAX_INDEX
        );
        let _ = fs::remove_dir_all(root).await;
    }
    #[tokio::test]
    async fn legacy_negative_is_ignored_without_discarding_positive_or_video() {
        let root = root();
        let mut cache = Cache::open(&root).await.unwrap();
        let motion = StoredMotion {
            collection_id: "1".into(),
            variants: vec![],
        };
        cache
            .set_metadata("legacy-negative".into(), None)
            .await
            .unwrap();
        cache
            .set_metadata("legacy-positive".into(), Some(motion))
            .await
            .unwrap();
        cache
            .index
            .metadata
            .get_mut("legacy-negative")
            .unwrap()
            .negative_schema = 0;
        cache
            .index
            .metadata
            .get_mut("legacy-positive")
            .unwrap()
            .negative_schema = 0;
        let path = cache.reserve("kept", 4).await.unwrap();
        fs::write(path, b"test").await.unwrap();
        cache
            .commit(AnimatedArtworkAsset {
                asset_id: "kept".into(),
                local_path: String::new(),
                codec: "h264".into(),
                width: 1080,
                height: 1080,
                frame_rate: 30.,
                size_bytes: 4,
            })
            .await
            .unwrap();
        // Simulate the previous on-disk schema, which had no negative_schema field.
        let mut json: serde_json::Value =
            serde_json::from_slice(&fs::read(Path::new(&root).join(INDEX)).await.unwrap()).unwrap();
        for metadata in json["metadata"].as_object_mut().unwrap().values_mut() {
            metadata.as_object_mut().unwrap().remove("negative_schema");
        }
        fs::write(
            Path::new(&root).join(INDEX),
            serde_json::to_vec(&json).unwrap(),
        )
        .await
        .unwrap();
        drop(cache);
        let mut cache = Cache::open(&root).await.unwrap();
        assert!(cache.metadata("legacy-negative").is_none());
        assert!(cache.metadata("legacy-positive").is_some());
        assert!(cache.lookup("kept").await.unwrap().is_some());
        assert_eq!(cache.disk_bytes().await.unwrap(), 4);
        cache
            .set_metadata("new-negative".into(), None)
            .await
            .unwrap();
        assert!(cache.metadata("new-negative").is_some());
        let _ = fs::remove_dir_all(root).await;
    }
}
