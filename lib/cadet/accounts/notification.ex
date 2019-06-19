defmodule Cadet.Accounts.Notification do
  @moduledoc """
  Provides the Notification schema as well as functions to
  fetch, write and acknowledge notifications.

  Also provides functions that implement notification sending when an
  assignment has been autograded or manually graded.
  """
  use Cadet, :model

  import Ecto.Query

  alias Cadet.Repo
  alias Cadet.Accounts.{Notification, NotificationType, Role, User}
  alias Cadet.Assessments.{Assessment, Question, Submission}
  alias Ecto.Multi

  schema "notifications" do
    field(:type, NotificationType)
    field(:read, :boolean)
    field(:role, Role, virtual: true)

    belongs_to(:user, User)
    belongs_to(:assessment, Assessment)
    belongs_to(:submission, Submission)
    belongs_to(:question, Question)

    timestamps()
  end

  @required_fields ~w(type read role user_id)a
  @optional_fields ~w(assessment_id submission_id question_id)a

  def changeset(answer, params) do
    answer
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_assessment_or_submission()
    |> foreign_key_constraint(:user)
    |> foreign_key_constraint(:assessment_id)
    |> foreign_key_constraint(:submission_id)
    |> foreign_key_constraint(:question_id)
  end

  defp validate_assessment_or_submission(changeset) do
    case get_change(changeset, :role) do
      :staff ->
        validate_required(changeset, [:submission_id])

      :student ->
        validate_required(changeset, [:assessment_id])

      _ ->
        add_error(changeset, :role, "Invalid role")
    end
  end

  @doc """
  Fetches all unread notifications belonging to a user as an array
  """
  @spec fetch(%User{}) :: {:ok, {:array, Notification}}
  def fetch(user = %User{}) do
    notifications =
      Notification
      |> where(user_id: ^user.id)
      |> where(read: false)
      |> Repo.all()

    {:ok, notifications}
  end

  @doc """
  Writes a new notification into the database
  """
  @spec write(:any) :: Ecto.Changeset.t()
  def write(params) do
    %Notification{}
    |> changeset(params)
    |> Repo.insert!()
  end

  @doc """
  Changes a notification's read status from false to true
  """
  @spec acknowledge(:integer, %User{}) :: {:ok, Ecto.Schema.t()} | {:error, :any}
  def acknowledge(notification_id, user = %User{}) do
    notification = Repo.get_by(Notification, id: notification_id, user_id: user.id)

    case notification do
      nil ->
        {:error, {:not_found, "Notification does not exist or does not belong to user"}}

      notification ->
        notification
        |> changeset(%{role: user.role, read: true})
        |> Repo.update()
    end
  end

  @doc """
  Writes a notification that a student's submission has been
  autograded successfully. (for the student)
  """
  @spec write_notification_when_autograded(integer() | String.t()) :: Ecto.Changeset.t()
  def write_notification_when_autograded(submission_id) do
    submission =
      Submission
      |> Repo.get_by(id: submission_id)

    params = %{
      type: :autograded,
      read: false,
      role: :student,
      user_id: submission.student_id,
      assessment_id: submission.assessment_id,
      submission_id: submission_id
    }

    write(params)
  end

  @doc """
  Writes a notification that a student's submission has been
  manually graded successfully by an Avenger or other teaching staff.
  (for the student)
  """
  @spec write_notification_when_manually_graded(integer() | String.t()) :: Ecto.Changeset.t()
  def write_notification_when_manually_graded(submission_id) do
    submission =
      Submission
      |> Repo.get_by(id: submission_id)

    params = %{
      type: :manually_graded,
      read: false,
      role: :student,
      user_id: submission.student_id,
      assessment_id: submission.assessment_id,
      submission_id: submission_id
    }

    write(params)
  end

  @doc """
  Writes a notification to all students that a new assessment is available.
  """
  @spec write_notification_for_new_assessment(integer() | String.t()) ::
          {:ok, any()}
          | {:error, any()}
          | {:error, Ecto.Multi.name(), any(), %{required(Ecto.Multi.name()) => any()}}
  def write_notification_for_new_assessment(assessment_id) do
    assessment =
      Assessment
      |> Repo.get_by(id: assessment_id)

    notification_multi = Multi.new()

    if Cadet.Assessments.is_open?(assessment) do
      User
      |> where(role: ^:student)
      |> Repo.all()
      |> Enum.each(fn %User{id: student_id} ->
        params = %{
          type: :new,
          read: false,
          role: :student,
          user_id: student_id,
          assessment_id: assessment_id
        }

        changes =
          %Notification{}
          |> changeset(params)

        Multi.insert(
          notification_multi,
          String.to_atom("notify_new_for_student_#{student_id}"),
          changes
        )
      end)

      Repo.transaction(notification_multi)
    end
  end

  @doc """
  When a student has finalized a submission, writes a notification to the corresponding
  grader (Avenger) in charge of the student.
  """
  @spec write_notification_when_student_submits(%Submission{}) :: Ecto.Changeset.t()
  def write_notification_when_student_submits(submission = %Submission{}) do
    leader_id =
      User
      |> Repo.get_by(id: submission.student_id)
      |> Repo.preload(:group)
      |> Map.get(:group)
      |> Map.get(:leader_id)

    params = %{
      type: :submitted,
      read: false,
      role: :staff,
      user_id: leader_id,
      assessment_id: submission.assessment_id,
      submission_id: submission.id
    }

    write(params)
  end
end
