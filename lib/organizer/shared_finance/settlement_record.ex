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

  @derive {
    Flop.Schema,
    filterable: [:method, :amount_cents, :transferred_at, :inserted_at],
    sortable: [:transferred_at, :amount_cents, :inserted_at],
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
    field :transferred_at, :utc_datetime
    belongs_to :settlement_cycle, Organizer.SharedFinance.SettlementCycle
    belongs_to :payer, Organizer.Accounts.User
    belongs_to :receiver, Organizer.Accounts.User
    has_many :allocations, Organizer.SharedFinance.SettlementRecordAllocation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settlement_record, attrs) do
    settlement_record
    |> cast(attrs, [:amount_cents, :method, :transferred_at])
    |> validate_required([:amount_cents, :method, :transferred_at])
    |> validate_number(:amount_cents, greater_than: 0)
  end

  def methods, do: @methods

  def method_label(method) when is_atom(method) do
    Map.get(@method_labels, method, String.upcase(to_string(method)))
  end

  def method_options do
    Enum.map(@methods, fn method ->
      {Map.fetch!(@method_labels, method), to_string(method)}
    end)
  end
end
