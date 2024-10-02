module Deadlinable
  extend ActiveSupport::Concern
  MIN_DAY_OF_MONTH = 1
  MAX_DAY_OF_MONTH = 28
  EVERY_NTH_COLLECTION = [["First", 1], ["Second", 2], ["Third", 3], ["Fourth", 4], ["Last", -1]].freeze
  DAY_OF_WEEK_COLLECTION = [["Sunday", 0], ["Monday", 1], ["Tuesday", 2], ["Wednesday", 3], ["Thursday", 4], ["Friday", 5], ["Saturday", 6]].freeze

  included do
    attr_accessor :by_month_or_week, :day_of_month, :day_of_week, :every_nth_day
    validates :deadline_day, numericality: {only_integer: true, less_than_or_equal_to: MAX_DAY_OF_MONTH,
                                            greater_than_or_equal_to: MIN_DAY_OF_MONTH, allow_nil: true}
    validate :reminder_on_deadline_day?, if: -> { day_of_month.present? }
    validate :reminder_is_within_range?, if: -> { day_of_month.present? }
    validates :by_month_or_week, inclusion: {in: %w[day_of_month day_of_week]}, if: -> { by_month_or_week.present? }
    validates :day_of_week, if: -> { day_of_week.present? }, inclusion: {in: %w[0 1 2 3 4 5 6]}
    validates :every_nth_day, if: -> { every_nth_day.present? }, inclusion: {in: %w[1 2 3 4 -1]}
  end

  def convert_to_reminder_schedule(day)
    schedule = IceCube::Schedule.new
    schedule.add_recurrence_rule IceCube::Rule.monthly.day_of_month(day)
    schedule.to_ical
  end

  def show_description(ical)
    schedule = IceCube::Schedule.from_ical(ical)
    schedule.recurrence_rules.first.to_s
  end

  def from_ical(ical)
    return if ical.blank?
    schedule = IceCube::Schedule.from_ical(ical)
    rule = schedule.recurrence_rules.first.instance_values
    day_of_month = rule["validations"][:day_of_month]&.first&.value

    results = {}
    results[:by_month_or_week] = day_of_month ? "day_of_month" : "day_of_week"
    results[:day_of_month] = day_of_month
    results[:day_of_week] = rule["validations"][:day_of_week]&.first&.day
    results[:every_nth_day] = rule["validations"][:day_of_week]&.first&.occ
    results
  rescue
    nil
  end

  def get_values_from_reminder_schedule
    return if reminder_schedule.blank?
    results = from_ical(reminder_schedule)
    return if results.nil?
    self.by_month_or_week = results[:by_month_or_week]
    self.day_of_month = results[:day_of_month]
    self.day_of_week = results[:day_of_week]
    self.every_nth_day = results[:every_nth_day]
  end

  private

  def reminder_on_deadline_day?
    if by_month_or_week == "day_of_month" && day_of_month.to_i == deadline_day
      errors.add(:day_of_month, "Reminder must not be the same as deadline date")
    end
  end

  def reminder_is_within_range?
    # IceCube converts negative or zero days to valid days (e.g. -1 becomes the last day of the month, 0 becomes 1)
    # The minimum check should no longer be necessary, but keeping it in case IceCube changes
    if by_month_or_week == "day_of_month" && day_of_month.to_i < MIN_DAY_OF_MONTH || day_of_month.to_i > MAX_DAY_OF_MONTH
      errors.add(:day_of_month, "Reminder day must be between #{MIN_DAY_OF_MONTH} and #{MAX_DAY_OF_MONTH}")
    end
  end

  def should_update_reminder_schedule
    if reminder_schedule.blank?
      return by_month_or_week.present?
    end
    sched = from_ical(reminder_schedule)
    by_month_or_week != sched[:by_month_or_week].presence.to_s ||
      day_of_month != sched[:day_of_month].presence.to_s ||
      day_of_week != sched[:day_of_week].presence.to_s ||
      every_nth_day != sched[:every_nth_day].presence.to_s
  end

  def create_schedule
    schedule = IceCube::Schedule.new(Time.zone.now.to_date)
    return nil if by_month_or_week.blank?
    if by_month_or_week == "day_of_month"
      return nil if day_of_month.blank?
      schedule.add_recurrence_rule(IceCube::Rule.monthly(1).day_of_month(day_of_month.to_i))
    else
      return nil if day_of_week.blank? || every_nth_day.blank?
      schedule.add_recurrence_rule(IceCube::Rule.monthly(1).day_of_week(day_of_week.to_i => [every_nth_day.to_i]))
    end
    schedule.to_ical
  rescue
    nil
  end
end
