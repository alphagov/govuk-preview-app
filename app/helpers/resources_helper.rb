module ResourcesHelper
  QUOTA_LABELS = {
    "requests.memory" => "Memory reserved",
    "limits.memory" => "Memory limits",
    "requests.storage" => "Storage",
    "pods" => "Pods",
    "persistentvolumeclaims" => "Volumes",
  }.freeze

  QUOTA_HINTS = {
    "requests.memory" => "What decides whether there's room for a preview - once it's full, the least recently used previews are put to sleep.",
    "limits.memory" => "The most pods could ever use between them, if every one reached its limit.",
  }.freeze

  # At or above these percentages, a meter shows as nearly full, then full.
  WARNING_PERCENT = 75
  DANGER_PERCENT = 90

  # MiB as "176 MiB" or, from 1 GiB, "1.5 GiB".
  def format_mi(mebibytes)
    return "#{mebibytes} MiB" if mebibytes < 1024

    "#{(mebibytes / 1024.0).round(1).to_s.delete_suffix('.0')} GiB"
  end

  def format_quota_value(row, value)
    row.counted? ? value.to_s : format_mi(value)
  end

  def quota_percent(row)
    return 0 unless row.hard.positive?

    [(row.used * 100.0 / row.hard).round, 100].min
  end

  # :normal, :warning or :danger - also said in words beside the meter,
  # never by colour alone.
  def quota_level(row)
    percent = quota_percent(row)
    if percent >= DANGER_PERCENT then :danger
    elsif percent >= WARNING_PERCENT then :warning
    else :normal
    end
  end

  def quota_label(row)
    QUOTA_LABELS.fetch(row.resource, row.resource)
  end

  def quota_hint(row)
    QUOTA_HINTS[row.resource]
  end

  # e.g. "5.2 GiB of 7 GiB (74%)"
  def quota_summary(row)
    "#{format_quota_value(row, row.used)} of #{format_quota_value(row, row.hard)} (#{quota_percent(row)}%)"
  end

  def stack_heading(root)
    "#{root.app_name} (#{root.branch})"
  end

  # A part's memory or storage, or nothing where it has none (most pods
  # claim no storage; a volume reserves no memory) - so a column only
  # draws the eye where there's something to see.
  def format_part_mi(mebibytes)
    mebibytes.positive? ? format_mi(mebibytes) : ""
  end
end
