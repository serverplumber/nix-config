{ ... }: {
  # Daily drop of the kernel's dentry/inode slab caches, then a compaction
  # pass, so iwlwifi can keep finding the physically contiguous memory it
  # needs.
  #
  # iwlmvm allocates TX queues on demand (DQA), each an order-6 (256 KiB)
  # contiguous DMA block with no fallback. After ~5 days of uptime the
  # Normal zone ran out of order-6 blocks and the kernel logged
  # `page allocation failure: order:6` / `iwlwifi: Tx queue alloc failed`
  # (Sep 29, Oct 3, Oct 5 2026 on one boot). Not a leak: ~16 GiB was still
  # available. The cause was ~3 million cached btrfs inodes (`btrfs_inode`
  # 3.3 GiB, plus their `dentry` and `lsm_inode_cache` entries) scattered
  # across memory. Slab is unmovable, so compaction alone can't form
  # large blocks around it.
  #
  # Measured by hand on 2026-10-05: `drop_caches=2` + `compact_memory` took
  # slab from 4.8 GiB to 1.2 GiB and free order-6 blocks in Normal from 20
  # to 518, with blocks up to order 10 reappearing. Not yet measured:
  # whether the allocation failures actually stop over a long uptime.
  #
  # Rejected alternatives:
  #   vm.min_free_kbytes  bigger reserve, same fragmentation; only delays it
  #   vm.vfs_cache_pressure  only acts under memory pressure, which this
  #                         machine rarely has
  #   drop_caches=3       also throws away the page cache; only the slab
  #                       matters here
  #
  # Cost: the first metadata-heavy job afterwards (nix eval, rg, fd) runs
  # cold once.
  systemd.services.drop-inode-cache = {
    description = "Drop dentry/inode caches and compact memory";
    serviceConfig.Type = "oneshot";
    script = ''
      sync
      echo 2 > /proc/sys/vm/drop_caches
      echo 1 > /proc/sys/vm/compact_memory
    '';
  };

  systemd.timers.drop-inode-cache = {
    wantedBy = [ "timers.target" ];
    # 03:00, clear of restic's daily walk of /home (00:00 + up to 30m), which
    # refills the inode cache; dropping just before it would be undone at
    # once. Not Persistent: a catch-up at boot would drop caches that are
    # minutes old in memory that isn't fragmented yet.
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      RandomizedDelaySec = "30m";
    };
  };
}
