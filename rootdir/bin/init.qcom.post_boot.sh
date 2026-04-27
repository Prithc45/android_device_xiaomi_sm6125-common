#! /vendor/bin/sh

# Copyright (c) 2012-2013, 2016-2020, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Tuned for Redmi Note 8 (ginkgo) - Snapdragon 665 (trinket)
# Optimized for: performance, battery, smoothness, multitasking
#

target=`getprop ro.board.platform`

function configure_read_ahead_kb_values() {
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    dmpts=$(ls /sys/block/*/queue/read_ahead_kb | grep -e dm -e mmc)

    # Set 128 for <= 3GB &
    # set 512 for >= 4GB targets.
    if [ $MemTotal -le 3145728 ]; then
        echo 128 > /sys/block/mmcblk0/bdi/read_ahead_kb
        echo 128 > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
        for dm in $dmpts; do
            echo 128 > $dm
        done
    else
        echo 512 > /sys/block/mmcblk0/bdi/read_ahead_kb
        echo 512 > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
        for dm in $dmpts; do
            echo 512 > $dm
        done
    fi

    # UFS specific read ahead (ginkgo uses UFS storage)
    echo 512 > /sys/block/sda/queue/read_ahead_kb
    echo 512 > /sys/block/sdf/queue/read_ahead_kb
}

function configure_memory_parameters() {
    # Set allocstall_threshold to 0 for all targets.
    echo 0 > /sys/module/vmpressure/parameters/allocstall_threshold

    # Tuned swappiness for 4GB RAM - lower is better for multitasking
    echo 60 > /proc/sys/vm/swappiness

    # Disable wsf because we are using efk.
    # wsf Range : 1..1000 So set to bare minimum value 1.
    echo 1 > /proc/sys/vm/watermark_scale_factor

    # VM dirty tuning - smoother writes, less I/O stutter
    echo 10 > /proc/sys/vm/dirty_ratio
    echo 5 > /proc/sys/vm/dirty_background_ratio
    echo 500 > /proc/sys/vm/dirty_expire_centisecs
    echo 3000 > /proc/sys/vm/dirty_writeback_centisecs

    configure_read_ahead_kb_values
}

case "$target" in
    "trinket")
        if [ -f /sys/devices/soc0/soc_id ]; then
            soc_id=`cat /sys/devices/soc0/soc_id`
        else
            soc_id=`cat /sys/devices/system/soc/soc0/id`
        fi

        case "$soc_id" in
            "394")

            # Core control parameters on big cluster
            echo 2 > /sys/devices/system/cpu/cpu4/core_ctl/min_cpus
            echo 40 > /sys/devices/system/cpu/cpu4/core_ctl/busy_down_thres
            echo 60 > /sys/devices/system/cpu/cpu4/core_ctl/busy_up_thres
            echo 100 > /sys/devices/system/cpu/cpu4/core_ctl/offline_delay_ms
            echo 1 > /sys/devices/system/cpu/cpu4/core_ctl/is_big_cluster
            echo 4 > /sys/devices/system/cpu/cpu4/core_ctl/task_thres

            # Tuned b.L scheduler migration thresholds
            # Lower upmigrate = tasks move to big cores more easily (perf)
            # Lower downmigrate = tasks come back to little cores sooner (battery)
            echo 60 > /proc/sys/kernel/sched_downmigrate
            echo 70 > /proc/sys/kernel/sched_upmigrate
            echo 75 > /proc/sys/kernel/sched_group_downmigrate
            echo 90 > /proc/sys/kernel/sched_group_upmigrate

            # cpuset settings - background tasks on little cores only
            echo 0-3 > /dev/cpuset/background/cpus
            echo 0-3 > /dev/cpuset/system-background/cpus

            # configure governor settings for little cluster (cpu0-3)
            # Max freq: 1.80 GHz (1804800 KHz)
            echo "schedutil" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
            echo 0 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/up_rate_limit_us
            echo 0 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/down_rate_limit_us
            # hispeed at ~78% of max — snappy but not power hungry
            echo 1401600 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_freq
            # min at 614.4 MHz — lowest available for battery saving
            echo 614400 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

            # configure governor settings for big cluster (cpu4-7)
            # Max freq: 2.02 GHz (2016000 KHz)
            echo "schedutil" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
            echo 0 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/up_rate_limit_us
            echo 0 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/down_rate_limit_us
            # hispeed at ~80% of max — good perf headroom
            echo 1612800 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/hispeed_freq
            # min at 768 MHz — lower than stock 1056MHz, better idle battery
            echo 768000 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq

            echo 1 > /proc/sys/kernel/sched_walt_rotate_big_tasks

            # sched_load_boost as -6 is equivalent to target load as 85. It is per cpu tunable.
            echo -6 > /sys/devices/system/cpu/cpu0/sched_load_boost
            echo -6 > /sys/devices/system/cpu/cpu1/sched_load_boost
            echo -6 > /sys/devices/system/cpu/cpu2/sched_load_boost
            echo -6 > /sys/devices/system/cpu/cpu3/sched_load_boost
            echo -6 > /sys/devices/system/cpu/cpu4/sched_load_boost
            echo -6 > /sys/devices/system/cpu/cpu5/sched_load_boost
            echo -6 > /sys/devices/system/cpu/cpu6/sched_load_boost
            echo -6 > /sys/devices/system/cpu/cpu7/sched_load_boost
            echo 85 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_load
            echo 85 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/hispeed_load

            # Foreground tasks prefer idle cores for lower latency
            echo 1 > /dev/stune/foreground/schedtune.prefer_idle

            # WALT history tuning - better task load tracking
            echo 10 > /proc/sys/kernel/sched_ravg_hist_size
            echo 1 > /proc/sys/kernel/sched_window_stats_policy

            # Set Memory parameters
            configure_memory_parameters

            # Enable bus-dcvs
            ddr_type=`od -An -tx /proc/device-tree/memory/ddr_device_type`
            ddr_type4="07"
            ddr_type3="05"

            for device in /sys/devices/platform/soc
            do
                for cpubw in $device/*cpu-cpu-ddr-bw/devfreq/*cpu-cpu-ddr-bw
                do
                    echo "bw_hwmon" > $cpubw/governor
                    echo 762 > $cpubw/min_freq
                    if [ ${ddr_type:4:2} == $ddr_type4 ]; then
                        # LPDDR4
                        echo "2288 3440 4173 5195 5859 7759 10322 11863 13763" > $cpubw/bw_hwmon/mbps_zones
                        echo 85 > $cpubw/bw_hwmon/io_percent
                    fi
                    if [ ${ddr_type:4:2} == $ddr_type3 ]; then
                        # LPDDR3
                        echo "1525 3440 5195 5859 7102" > $cpubw/bw_hwmon/mbps_zones
                        echo 34 > $cpubw/bw_hwmon/io_percent
                    fi
                    echo 4 > $cpubw/bw_hwmon/sample_ms
                    echo 90 > $cpubw/bw_hwmon/decay_rate
                    echo 190 > $cpubw/bw_hwmon/bw_step
                    echo 20 > $cpubw/bw_hwmon/hist_memory
                    echo 0 > $cpubw/bw_hwmon/hyst_length
                    echo 80 > $cpubw/bw_hwmon/down_thres
                    echo 0 > $cpubw/bw_hwmon/guard_band_mbps
                    echo 250 > $cpubw/bw_hwmon/up_scale
                    echo 1600 > $cpubw/bw_hwmon/idle_mbps
                    echo 50 > $cpubw/polling_interval
                done

            done

            # memlat specific settings are moved to separate file under
            # device/target specific folder
            setprop vendor.dcvs.prop 1

            # colocation v3 disabled
            echo 0 > /proc/sys/kernel/sched_min_task_util_for_boost
            echo 0 > /proc/sys/kernel/sched_min_task_util_for_colocation
            echo 0 > /proc/sys/kernel/sched_little_cluster_coloc_fmin_khz

            # Turn off scheduler boost at the end
            echo 0 > /proc/sys/kernel/sched_boost

            # Turn on sleep modes.
            echo 0 > /sys/module/lpm_levels/parameters/sleep_disabled

            ;;
        esac
    ;;
esac

# Post-setup services
case "$target" in
    "trinket")
        setprop vendor.post_boot.parsed 1

        # Enable PowerHAL hint processing
        setprop vendor.powerhal.init 1
    ;;
esac

# Let kernel know our image version/variant/crm_version
if [ -f /sys/devices/soc0/select_image ]; then
    image_version="10:"
    image_version+=`getprop ro.build.id`
    image_version+=":"
    image_version+=`getprop ro.build.version.incremental`
    image_variant=`getprop ro.product.name`
    image_variant+="-"
    image_variant+=`getprop ro.build.type`
    oem_version=`getprop ro.build.version.codename`
    echo 10 > /sys/devices/soc0/select_image
    echo $image_version > /sys/devices/soc0/image_version
    echo $image_variant > /sys/devices/soc0/image_variant
    echo $oem_version > /sys/devices/soc0/image_crm_version
fi
