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
  alias Cadet.Assessments.{Answer, Assessment, Question, Submission}

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

  def check_for_not_yet_autograded(answer = %Answer{}) do
    status = answer.autograding_status
    status == :none or status == :processing
  end

  @doc """
  Attempts to send a notification for successful autograding of a submission.
  This should be called when an answer has been seen by the autograder.

  Specifically, tests whether there are still un-autograded answers within that submission.
  If there are no un-autograded answers, assume the submission is fully autograded,
  and send a notification to the student who submitted the answer.
  If answers that are not yet autograded exist, do nothing.
  """
  @spec write_notification_when_autograded(integer()) ::
          Ecto.Changeset.t() | {:failure, String.t()}
  def write_notification_when_autograded(answer_id) do
    answer =
      Answer
      |> Repo.get_by(id: answer_id)

    submission =
      Submission
      |> Repo.get_by(id: answer.submission_id)

    find_ungraded_answer =
      submission
      |> Ecto.assoc(:answers)
      |> Repo.all()
      |> Enum.find(&Notification.check_for_not_yet_autograded/1)

    if find_ungraded_answer == nil do
      # Autograded the last answer of the submission      
      params = %{
        type: :autograded,
        read: false,
        role: :student,
        user_id: submission.student_id,
        assessment_id: submission.assessment_id,
        submission_id: submission.id
      }

      Notification.write(params)
    else
      # Have not finished autograding the entire submission
      {:failure, "Autograding for submission #{submission.id} still not complete"}
    end
  end

  @doc """
  Attempts to send a notification to the student after an answer has been graded.

  First, checks if the entire submission has been graded.
  If it has, then the notification that a student's submission has been
  (manually) graded successfully by an Avenger or other teaching staff is written.
  (for the student)

  If not, it will not be sent.
  """
  @spec write_notification_when_manually_graded(integer() | String.t()) ::
          Ecto.Changeset.t() | {:failure, String.t()}
  def write_notification_when_manually_graded(submission_id) do
    submission =
      Submission
      |> Repo.get_by(id: submission_id)

    question_count =
      Question
      |> where(assessment_id: ^submission.assessment_id)
      |> select([q], count(q.id))
      |> Repo.one()

    graded_count =
      Answer
      |> where([a], submission_id: ^submission_id)
      |> where([a], not is_nil(a.grader_id))
      |> select([a], count(a.id))
      |> Repo.one()

    if question_count == graded_count do
      # Every answer in this submission has been graded manually
      params = %{
        type: :graded,
        read: false,
        role: :student,
        user_id: submission.student_id,
        assessment_id: submission.assessment_id,
        submission_id: submission_id
      }

      Notification.write(params)
    else
      # Manual grading for the entire submission has not been completed
      {:failure, "Manual grading for submission #{submission_id} still not complete"}
    end
  end
end
