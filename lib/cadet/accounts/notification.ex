defmodule Cadet.Accounts.Notification do
  use Cadet, :model

  alias Cadet.Repo
  alias Cadet.Accounts.NotificationType
  alias Cadet.Accounts.User
  alias Cadet.Assessments.Question
  alias Cadet.Assessments.Submission

  schema "notification" do
    field(:type, NotificationType)
    field(:read, :boolean)

    belongs_to(:user, User)
    belongs_to(:submission, Submission)
    belongs_to(:question, Question)

    timestamps()
  end

  @required_fields ~w(type read user_id submission_id question_id)a

  def changeset(answer, params) do
    answer
    |> cast(params, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:user)
    |> foreign_key_constraint(:submission_id)
    |> foreign_key_constraint(:question_id)
  end

  """
  # Consider another time
  @spec poll :: {:ok, :integer}
  def poll() do

  end
  """

  @doc """
  Fetches all notifications belonging to a user as an array
  """
  @spec fetch(:any) :: {:ok, {:array, Notification}}
  def fetch(params) do
  end

  @doc """
  Writes a new notification into the database
  """
  @spec write(:any) :: Ecto.Changeset.t()
  def write(params) do
  end

  @doc """
  Changes a notification's read status from false to true
  """
  @spec acknowledge(:any) :: Ecto.Changeset.t()
  def acknowledge(params) do
  end
end
