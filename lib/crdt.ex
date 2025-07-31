defmodule CRDT do

  @moduledoc """
  Documentation for `CRDT`.

  This module defines types, callbacks for behaviours and the functions that use them.
  It ensures only valid CRDTs are created.
  New updates are created by local downstream operations and upon being received applied as updates.
  The require_state_downstream callback states if the crdt's local state is needed to create the downstream effect / update or not.

  Naming pattern for CRDTs: <type>_<semantics>_<OB|SB>

  CRDTs provided:
  Counter_PN_OB: PN-Counter aka Positive Negative Counter (operation-based)
  Counter_PN_SB: PN-Counter aka Positive Negative Counter (state-based) 
  Set_AW_OP: Add-wins set (operation-based)
  Set_RW_OP: Remove-wins set (operation-based)
  MV_Register: Multi-value register (operation-based)
  LWW_Register: Last-writer-wins register (operation-based)
  """

  # ToDo: Improve type spec

  @type t :: :set_aw_op | :counter_pn_ob | :mv_register | :counter_pn_sb | :set_rw_op | :lww_register
  @type crdt :: t
  @type update :: {atom, term}
  @type effect :: term
  @type value :: term
  @type reason :: term

  @type internal_crdt :: term
  @type internal_effect :: term

  @callback new() :: internal_crdt()
  @callback value(internal_value :: internal_crdt) :: value()
  @callback downstream(update(), internal_crdt()) :: {:ok, internal_effect()} | {:error, reason}
  @callback update(internal_effect(), internal_crdt()) :: {:ok, internal_crdt()}
  @callback require_state_downstream(update :: update()) :: {:ok, internal_crdt()}

  @callback equal(internal_crdt(), internal_crdt()) :: boolean()

  # ToDo: Add new types as needed
  defguard valid?(type)
  when
  (type == :set_aw_op) or
  (type == :counter_pn_ob) or
  (type == :mv_register) or
  (type == :counter_pn_sb) or
  (type == :set_rw_op) or
  (type == :lww_register)


  def new(type) when valid?(type) do
    get_module(type).new()
  end

  def value(type, state) do
    get_module(type).value(state)
  end

  def downstream(type, update, state) do
    get_module(type).downstream(update, state)
  end

  def update(type, effect, state) do
    get_module(type).update(effect, state)
  end

  def require_state_downstream(type, update) do
    get_module(type).require_state_downstream(update)
  end

  defp get_module(:set_aw_op), do: Set_AW_OP
  defp get_module(:counter_pn_ob), do: Counter_PN_OB  
  defp get_module(:mv_register), do: MV_Register
  defp get_module(:counter_pn_sb), do: Counter_PN_SB
  defp get_module(:set_rw_op), do: Set_RW_OP
  defp get_module(:lww_register), do: LWW_Register

  @spec to_binary(internal_crdt()) :: binary()
  def to_binary(term) do
    :erlang.term_to_binary(term)
  end

  @spec from_binary(binary()) :: {:ok, internal_crdt()} | {:error, reason()}
  def from_binary(binary) do
    :erlang.binary_to_term(binary)
  end
end
