#!/bin/bash

shopt -s nullglob

for hwmon in /sys/class/hwmon/hwmon*; do
  [[ -r "$hwmon/name" ]] || continue
  IFS= read -r name <"$hwmon/name"
  [[ "$name" == "coretemp" || "$name" == "k10temp" || "$name" == "zenpower" ]] || continue

  selected=""
  for label_file in "$hwmon"/temp*_label; do
    IFS= read -r label <"$label_file"
    if [[ "$label" == "Package id 0" || "$label" == "Tctl" ]]; then
      candidate="${label_file%_label}_input"
      [[ -r "$candidate" ]] && selected="$candidate"
      break
    fi
  done

  if [[ -z "$selected" ]]; then
    for candidate in "$hwmon"/temp*_input; do
      [[ -r "$candidate" ]] && selected="$candidate" && break
    done
  fi

  if [[ -n "$selected" ]]; then
    printf 'cpu_temp\t%s\n' "$selected"
    break
  fi
done

for block_path in /sys/class/block/*; do
  device="${block_path##*/}"
  [[ -e "$block_path/partition" ]] && continue
  [[ -e "$block_path/device" ]] || continue
  case "$device" in
    loop*|ram*|zram*|fd*|sr*) continue ;;
  esac
  printf 'disk\t%s\n' "$device"
done

# GPU: pick the card exposing the most VRAM, which is the discrete one on
# hybrid systems. The integrated adapter shares system RAM and reports a few
# hundred megabytes, so the comparison separates them without hardcoding IDs.
best_vram=-1
gpu_busy=""
gpu_temp=""
gpu_vram_used=""
gpu_vram_total=""

for card in /sys/class/drm/card*; do
  name="${card##*/}"
  [[ "$name" =~ ^card[0-9]+$ ]] || continue
  device="$card/device"
  # gpu_busy_percent is the amdgpu utilisation counter. Cards that do not
  # publish it (nouveau, the proprietary NVIDIA stack) are skipped rather
  # than reported as 0%, which would read as an idle GPU.
  [[ -r "$device/gpu_busy_percent" ]] || continue

  vram=0
  [[ -r "$device/mem_info_vram_total" ]] && IFS= read -r vram <"$device/mem_info_vram_total"
  [[ "$vram" =~ ^[0-9]+$ ]] || vram=0
  (( vram > best_vram )) || continue

  best_vram=$vram
  gpu_busy="$device/gpu_busy_percent"
  gpu_vram_used=""
  gpu_vram_total=""
  gpu_temp=""
  [[ -r "$device/mem_info_vram_used" ]] && gpu_vram_used="$device/mem_info_vram_used"
  [[ -r "$device/mem_info_vram_total" ]] && gpu_vram_total="$device/mem_info_vram_total"
  for hwmon in "$device"/hwmon/hwmon*; do
    [[ -r "$hwmon/temp1_input" ]] || continue
    gpu_temp="$hwmon/temp1_input"
    break
  done
done

[[ -n "$gpu_busy" ]] && printf 'gpu_busy\t%s\n' "$gpu_busy"
[[ -n "$gpu_temp" ]] && printf 'gpu_temp\t%s\n' "$gpu_temp"
[[ -n "$gpu_vram_used" ]] && printf 'gpu_vram_used\t%s\n' "$gpu_vram_used"
[[ -n "$gpu_vram_total" ]] && printf 'gpu_vram_total\t%s\n' "$gpu_vram_total"
exit 0
