defmodule Organizer.SharedFinance.SettlementRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @methods [
    :pix,
    :ted,
    :doc,
    :dinheiro,
    :boleto,
    :transferencia_entre_contas,
    :cartao_debito,
    :cartao_credito,
    :cheque,
    :outro
  ]

  @method_labels %{
    pix: "PIX",
    ted: "TED",
    doc: "DOC",
    dinheiro: "Dinheiro",
    boleto: "Boleto",
    transferencia_entre_contas: "Transferência entre contas",
    cartao_debito: "Cartão de débito",
    cartao_credito: "Cartão de crédito",
    cheque: "Cheque",
    outro: "Outro"
  }

  @statuses [:active, :reversed]

  @derive {
    Flop.Schema,
    filterable: [:method, :amount_cents, :transferred_at, :status, :inserted_at],
    sortable: [:transferred_at, :amount_cents, :status, :inserted_at],
    default_order: %{
      order_by: [:transferred_at, :inserted_at],
      order_directions: [:desc, :desc]
    },
    default_limit: 20,
    max_limit: 100
  }

  schema "settlement_records" do
    field :amount_cents, :integer
    field :method, Ecto.Enum, values: @methods
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :transferred_at, :utc_datetime
    field :reversed_at, :utc_datetime
    field :reversal_reason, :string
    belongs_to :settlement_cycle, Organizer.SharedFinance.SettlementCycle
    belongs_to :payer, Organizer.Accounts.User
    belongs_to :receiver, Organizer.Accounts.User
    belongs_to :reversed_by, Organizer.Accounts.User
    has_many :allocations, Organizer.SharedFinance.SettlementRecordAllocation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settlement_record, attrs) do
    settlement_record
    |> cast(attrs, [
      :amount_cents,
      :method,
      :status,
      :transferred_at,
      :reversed_at,
      :reversal_reason,
      :reversed_by_id
    ])
    |> validate_required([:amount_cents, :method, :status, :transferred_at])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_length(:reversal_reason, max: 300)
  end

  def methods, do: @methods
  def statuses, do: @statuses

  def method_label(method) when is_atom(method) do
    Map.get(@method_labels, method, String.upcase(to_string(method)))
  end

  def method_options do
    Enum.map(@methods, fn method ->
      {Map.fetch!(@method_labels, method), to_string(method)}
    end)
  end
end
