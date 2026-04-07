defmodule Example.WithBlock do
  def fetch_user_data(user_id, org_id) do
    with {:ok, user} <- Repo.fetch(User, user_id),
         {:ok, org} <- Repo.fetch(Org, org_id),
         {:ok, membership} <- Repo.find_membership(user, org),
         true <- membership.active do
      {:ok, %{user: user, org: org, membership: membership}}
    else
      {:error, :not_found} -> {:error, :resource_not_found}
      {:error, reason} -> {:error, reason}
      false -> {:error, :inactive_membership}
    end
  end

  def pipeline_with(input) do
    with {:ok, parsed} <- Jason.decode(input),
         {:ok, validated} <- validate(parsed),
         result <- transform(validated) do
      {:ok, result}
    end
  end
end
