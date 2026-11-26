use std::sync::atomic::Ordering::Relaxed;

/// One line of MiB figures from existing counters. Off by default: callers
/// decide when/if to log it. This is attribution-only; it does not change
/// allocation behavior.
pub fn report() -> String {
    let mib = |v: u64| v >> 20;
    let mut line = String::from("memory:");

    #[cfg(windows)]
    {
        use std::fmt::Write;
        let alive: Vec<u64> = crate::host::ALIVE.iter().map(|a| a.load(Relaxed)).collect();
        let made: Vec<u64> = crate::host::MADE.iter().map(|a| a.load(Relaxed)).collect();
        let lists: Vec<u64> = crate::host::LISTS.iter().map(|a| a.load(Relaxed)).collect();
        let retired: Vec<u64> = crate::host::RETIRED_STATS.iter().map(|a| a.load(Relaxed)).collect();
        let _ = write!(
            line,
            " host lists alive {}, scratch chunks alive {} ({} MiB, spare {} / {} MiB, reused {}), other upload buffers alive {} ({} MiB), lists made {}, preludes {}, never-reset alive {}, retired queued {} (res {} MiB, any {})",
            alive.get(0).copied().unwrap_or(0),
            alive.get(1).copied().unwrap_or(0),
            mib(alive.get(2).copied().unwrap_or(0)),
            alive.get(3).copied().unwrap_or(0),
            mib(alive.get(4).copied().unwrap_or(0)),
            alive.get(5).copied().unwrap_or(0),
            alive.get(6).copied().unwrap_or(0),
            mib(alive.get(7).copied().unwrap_or(0)),
            lists.get(0).copied().unwrap_or(0),
            lists.get(1).copied().unwrap_or(0),
            lists.get(3).copied().unwrap_or(0),
            retired.get(0).copied().unwrap_or(0),
            mib(retired.get(1).copied().unwrap_or(0)),
            retired.get(2).copied().unwrap_or(0),
        );

        #[cfg(feature = "diagnostics")]
        {
            let shadows = crate::shadow::memory();
            let staged = crate::texture::memory();
            let windows = crate::shadow::windows();
            let host_tex: Vec<u64> = crate::resource::HOST_TEXTURES.iter().map(|a| a.load(Relaxed)).collect();
            let placed = crate::resource::placed_textures();
            let _ = write!(
                line,
                "; shadows {} ({} MiB, windows {} / {} MiB, let-go {} / {} MiB, asked-span {} MiB), snapshot pool {} ({} MiB); staging {} ({} MiB, kept {})",
                shadows[0], mib(shadows[1]), shadows[2], mib(shadows[3]), windows[0], mib(windows[1]), mib(windows[2]), shadows[4], mib(shadows[5]),
                staged[0], mib(staged[1]), staged[2],
            );
            let _ = write!(
                line,
                "; host textures {} ({} MiB, placed {}); upload/readback/shared/ua/texheap/tileheap made MiB [{}, {}, {}, {}, {}, {}]",
                host_tex.get(0).copied().unwrap_or(0), mib(host_tex.get(1).copied().unwrap_or(0)), placed,
                mib(made.get(0).copied().unwrap_or(0)),
                mib(made.get(1).copied().unwrap_or(0)),
                mib(made.get(2).copied().unwrap_or(0)),
                mib(made.get(3).copied().unwrap_or(0)),
                mib(made.get(4).copied().unwrap_or(0)),
                mib(made.get(5).copied().unwrap_or(0)),
            );
            if let Some(h) = crate::host::host() {
                if let Some([budget, used, shared_budget, shared_used]) = h.video_memory() {
                    let _ = write!(
                        line,
                        "; video {} / {} MiB, shared {} / {} MiB",
                        mib(used), mib(budget), mib(shared_used), mib(shared_budget)
                    );
                }
            }
        }
    }

    #[cfg(not(windows))]
    {
        line.push_str(" unavailable");
    }

    line
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn report_has_memory_prefix() {
        let line = report();
        assert!(line.starts_with("memory:"), "{line}");
    }

    #[cfg(windows)]
    #[test]
    fn report_mentions_host_lists() {
        let line = report();
        assert!(line.contains("host lists alive"), "{line}");
        assert!(line.contains("scratch chunks alive"), "{line}");
        assert!(line.contains("retired queued"), "{line}");
    }
}


