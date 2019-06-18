import EctoEnum

defenum(Cadet.Accounts.NotificationType, :notification_type, [
  # Notifications for new assessments
  :new,

  # Notifications for deadlines
  :deadline,

  # Notifications for autograded assessments
  :autograded,

  # Notifications for manually graded assessments
  :manually_graded,

  # Notifications for submitted assessments
  :submitted
])
