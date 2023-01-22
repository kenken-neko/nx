defmodule Nx.LinAlg do
  @moduledoc """
  Nx conveniences for linear algebra.

  This module can be used in `defn`.
  """

  import Nx.Shared
  import Nx.Defn, only: [defn: 2, defnp: 2, deftransformp: 2]
  import Nx.Defn.Kernel, only: [keyword!: 2]

  alias Nx.Tensor, as: T

  @doc """
  Returns the adjoint of a given tensor.

  If the input tensor is real it transposes it's two inner-most axes.
  If the input tensor is complex, it additionally applies `Nx.conjugate/1` to it.

  ## Examples

      iex> Nx.LinAlg.adjoint(Nx.tensor([[1, 2], [3, 4]]))
      #Nx.Tensor<
        s64[2][2]
        [
          [1, 3],
          [2, 4]
        ]
      >

      iex> Nx.LinAlg.adjoint(Nx.tensor([[1, Complex.new(0, 2)], [3, Complex.new(0, -4)]]))
      #Nx.Tensor<
        c64[2][2]
        [
          [1.0+0.0i, 3.0+0.0i],
          [0.0-2.0i, 0.0+4.0i]
        ]
      >
  """
  defn adjoint(t) do
    tensor = Nx.to_tensor(t)
    opts = adjoint_opts(tensor.shape)

    case Nx.type(tensor) do
      {:c, _} ->
        tensor |> Nx.transpose(opts) |> Nx.conjugate()

      _ ->
        Nx.transpose(tensor, opts)
    end
  end

  deftransformp adjoint_opts(shape) do
    rank = tuple_size(shape)

    if rank > 2 do
      axes = Enum.concat(0..(rank - 3), [rank - 1, rank - 2])
      [axes: axes]
    else
      []
    end
  end

  @doc """
  Performs a Cholesky decomposition of a batch of square matrices.

  The matrices must be positive-definite and either Hermitian
  if complex or symmetric if real. An error is raised by the
  default backend if those conditions are not met. Other
  backends may emit undefined behaviour.

  ### Examples
      iex> Nx.LinAlg.cholesky(Nx.tensor([[20.0, 17.6], [17.6, 16.0]]))
      #Nx.Tensor<
        f32[2][2]
        [
          [4.4721360206604, 0.0],
          [3.9354796409606934, 0.7155413031578064]
        ]
      >

      iex> Nx.LinAlg.cholesky(Nx.tensor([[[2.0, 3.0], [3.0, 5.0]], [[1.0, 0.0], [0.0, 1.0]]]))
      #Nx.Tensor<
        f32[2][2][2]
        [
          [
            [1.4142135381698608, 0.0],
            [2.1213202476501465, 0.7071067690849304]
          ],
          [
            [1.0, 0.0],
            [0.0, 1.0]
          ]
        ]
      >

      iex> t = Nx.tensor([
      ...>   [6.0, 3.0, 4.0, 8.0],
      ...>   [3.0, 6.0, 5.0, 1.0],
      ...>   [4.0, 5.0, 10.0, 7.0],
      ...>   [8.0, 1.0, 7.0, 25.0]
      ...> ])
      iex> Nx.LinAlg.cholesky(t)
      #Nx.Tensor<
        f32[4][4]
        [
          [2.4494898319244385, 0.0, 0.0, 0.0],
          [1.2247449159622192, 2.1213202476501465, 0.0, 0.0],
          [1.632993221282959, 1.4142135381698608, 2.309401035308838, 0.0],
          [3.265986442565918, -1.4142135381698608, 1.5877132415771484, 3.132491111755371]
        ]
      >

      iex> Nx.LinAlg.cholesky(Nx.tensor([[1.0, Complex.new(0, -2)], [Complex.new(0, 2), 5.0]]))
      #Nx.Tensor<
        c64[2][2]
        [
          [1.0+0.0i, 0.0+0.0i],
          [0.0+2.0i, 1.0+0.0i]
        ]
      >

  ### Error cases

      iex> Nx.LinAlg.cholesky(Nx.tensor([[1.0, 2.0], [3.0, 4.0]]))
      ** (ArgumentError) matrix must be hermitian, a matrix is hermitian iff X = adjoint(X)
  """
  def cholesky(tensor) do
    %T{type: type, shape: shape, names: names} = tensor = Nx.to_tensor(tensor)

    output_type = Nx.Type.to_floating(type)

    {output_shape, output_names} = Nx.Shape.cholesky(shape, names)

    out = %{tensor | type: output_type, shape: output_shape, names: output_names}
    impl!(tensor).cholesky(out, tensor)
  end

  @doc """
  Calculates the p-norm of a tensor.

  For the 0-norm, the norm is the number of non-zero elements in the tensor.

  ## Options

    * `:axes` - defines the axes upon which the norm will be calculated.
      Applies only on 2-norm for 2-D tensors. Default: `nil`.
    * `:ord` - defines which norm will be calculated according to the table below. Default: `2`

  | ord          | 2-D                            | 1-D                               |
  | ------------ | -------------------------------| --------------------------------- |
  | `nil`        | Frobenius norm                 | 2-norm                            |
  | `:nuclear`   | Nuclear norm                   | -                                 |
  | `:frobenius` | Frobenius norm                 | -                                 |
  | `:inf`       | `max(sum(abs(x), axes: [1]))`  | `max(abs(x))`                     |
  | `:neg_inf`   | `min(sum(abs(x), axes: [1]))`  | `min(abs(x))`                     |
  | 0            | -                              | Number of non-zero elements       |
  | 1            | `max(sum(abs(x), axes: [0]))`  | as below                          |
  | -1           | `min(sum(abs(x), axes: [0]))`  | as below                          |
  | 2            | 2-norm                         | as below                          |
  | -2           | smallest singular value        | as below                          |
  | other        | -                              | power(sum(power(abs(x), p)), 1/p) |

  ## Examples

  ### Vector norms

      iex> Nx.LinAlg.norm(Nx.tensor([3, 4]))
      #Nx.Tensor<
        f32
        5.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([3, 4]), ord: 1)
      #Nx.Tensor<
        f32
        7.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([3, -4]), ord: :inf)
      #Nx.Tensor<
        f32
        4.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([3, -4]), ord: :neg_inf)
      #Nx.Tensor<
        f32
        3.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([3, -4, 0, 0]), ord: 0)
      #Nx.Tensor<
        f32
        2.0
      >

  ### Matrix norms

      iex> Nx.LinAlg.norm(Nx.tensor([[3, -1], [2, -4]]), ord: -1)
      #Nx.Tensor<
        f32
        5.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[3, -2], [2, -4]]), ord: 1)
      #Nx.Tensor<
        f32
        6.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[3, -2], [2, -4]]), ord: :neg_inf)
      #Nx.Tensor<
        f32
        5.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[3, -2], [2, -4]]), ord: :inf)
      #Nx.Tensor<
        f32
        6.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[3, 0], [0, -4]]), ord: :frobenius)
      #Nx.Tensor<
        f32
        5.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[1, 0, 0], [0, -4, 0], [0, 0, 9]]), ord: :nuclear)
      #Nx.Tensor<
        f32
        14.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[1, 0, 0], [0, -4, 0], [0, 0, 9]]), ord: -2)
      #Nx.Tensor<
        f32
        1.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[3, 0], [0, -4]]))
      #Nx.Tensor<
        f32
        5.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[3, 4], [0, -4]]), axes: [1])
      #Nx.Tensor<
        f32[2]
        [5.0, 4.0]
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[Complex.new(0, 3), 4], [4, 0]]), axes: [0])
      #Nx.Tensor<
        f32[2]
        [5.0, 4.0]
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[Complex.new(0, 3), 0], [4, 0]]), ord: :neg_inf)
      #Nx.Tensor<
        f32
        3.0
      >

      iex> Nx.LinAlg.norm(Nx.tensor([[0, 0], [0, 0]]))
      #Nx.Tensor<
        f32
        0.0
      >

  ### Error cases

      iex> Nx.LinAlg.norm(Nx.tensor([3, 4]), ord: :frobenius)
      ** (ArgumentError) expected a 2-D tensor for ord: :frobenius, got a 1-D tensor
  """
  @doc from_backend: false
  defn norm(tensor, opts \\ []) do
    opts = keyword!(opts, [:ord, :axes])
    norm_transform(tensor, opts)
  end

  deftransformp norm_transform(t, opts) do
    rank = Nx.rank(t)

    unless rank == 1 or rank == 2 do
      raise ArgumentError, "expected 1-D or 2-D tensor, got tensor with shape #{inspect(t.shape)}"
    end

    axes_opts = Keyword.take(opts, [:axes])

    case opts[:ord] do
      nil when rank == 1 -> norm_integer(t, 2, axes_opts)
      nil when rank == 2 -> norm_integer(t, 2, axes_opts)
      :frobenius -> norm_frobenius(t, axes_opts)
      :nuclear when rank == 2 -> norm_nuclear(t)
      :nuclear -> raise ArgumentError, "nuclear norm not supported for rank != 2"
      ord when ord in [:inf, :neg_inf] -> norm_inf(t, ord, axes_opts)
      ord when is_integer(ord) -> norm_integer(t, ord, axes_opts)
      ord -> raise ArgumentError, "unknown ord #{inspect(ord)}"
    end
  end

  defp norm_frobenius(%{shape: {_}}, _opts),
    do: raise(ArgumentError, "expected a 2-D tensor for ord: :frobenius, got a 1-D tensor")

  defp norm_frobenius(%{shape: {_, _}} = t, opts), do: norm_integer(t, 2, opts)

  defp norm_nuclear(%{shape: {_, _}} = t) do
    {_u, s, _v} = svd(t)
    Nx.sum(s)
  end

  defp norm_inf(%{shape: shape, type: type} = t, ord, _opts) when ord in [:inf, :neg_inf] do
    output_type = Nx.Type.to_real(type)
    aggregate_axes = if tuple_size(shape) == 2, do: &Nx.sum(&1, axes: [1]), else: & &1
    reduce = if ord == :inf, do: &Nx.reduce_max/1, else: &Nx.reduce_min/1

    t
    |> Nx.abs()
    |> aggregate_axes.()
    |> reduce.()
    |> Nx.as_type(output_type)
  end

  defp norm_integer(%{shape: {_}, type: type} = t, 0, _opts) do
    output_type = Nx.Type.to_real(type)

    t
    |> Nx.not_equal(0)
    |> Nx.sum()
    |> Nx.as_type(output_type)
  end

  defp norm_integer(%{shape: {_, _}, type: type} = t, ord, _opts) when ord in [1, -1] do
    output_type = Nx.Type.to_real(type)
    function = if ord == 1, do: &Nx.reduce_max/1, else: &Nx.reduce_min/1

    t
    |> Nx.abs()
    |> Nx.sum(axes: [0])
    |> function.()
    |> Nx.as_type(output_type)
  end

  defp norm_integer(%{shape: {_, _}}, ord, _opts) when ord not in [-2, -1, 1, 2] do
    raise ArgumentError, "invalid :ord for 2-D tensor, got: #{inspect(ord)}"
  end

  defp norm_integer(%{shape: {_, _}} = t, -2, _opts) do
    {_u, s, _v} = Nx.LinAlg.svd(t)
    Nx.reduce_min(s)
  end

  defp norm_integer(%{type: type} = t, ord, opts) when is_integer(ord) do
    output_type = Nx.Type.to_real(type)
    inv_ord = Nx.tensor(1 / ord, type: output_type)

    # We extract this result to a variable because it's used both for
    # getting the normalization coefficient and for the main pipe chain
    abs_t = Nx.abs(t)

    # This coefficient is introduced for better numerical stability
    # The idea is that by dividing the tensor by it, large values of
    # tensor entries and large values of p are reduced, which in turn
    # avoids numerical overflow.
    numerical_stability_coefficient = Nx.reduce_max(abs_t)

    # This code prevents from division by zero.
    numerical_stability_coefficient =
      Nx.select(
        Nx.greater(numerical_stability_coefficient, 0),
        numerical_stability_coefficient,
        1
      )

    abs_t
    |> Nx.divide(numerical_stability_coefficient)
    |> Nx.power(ord)
    |> Nx.sum(opts)
    |> Nx.power(inv_ord)
    |> Nx.multiply(numerical_stability_coefficient)
  end

  @doc """
  Solve the equation `a x = b` for x, assuming `a` is a batch of triangular matrices.
  Can also solve `x a = b` for x. See the `:left_side` option below.

  `b` must either be a batch of square matrices with the same dimensions as `a` or a batch of 1-D tensors
  with as many rows as `a`. Batch dimensions of `a` and `b` must be the same.

  ## Options

  The following options are defined in order of precedence

  * `:transform_a` - Defines `op(a)`, depending on its value. Can be one of:
    * `:none` -> `op(a) = a`
    * `:transpose` -> `op(a) = transpose(a)`
    Defaults to `:none`
  * `:lower` - When `true`, defines the `a` matrix as lower triangular. If false, a is upper triangular.
    Defaults to `true`
  * `:left_side` - When `true`, solves the system as `op(A).X = B`. Otherwise, solves `X.op(A) = B`. Defaults to `true`.

  ## Examples

      iex> a = Nx.tensor([[3, 0, 0, 0], [2, 1, 0, 0], [1, 0, 1, 0], [1, 1, 1, 1]])
      iex> Nx.LinAlg.triangular_solve(a, Nx.tensor([4, 2, 4, 2]))
      #Nx.Tensor<
        f32[4]
        [1.3333333730697632, -0.6666666865348816, 2.6666667461395264, -1.3333333730697632]
      >

      iex> a = Nx.tensor([[1, 0, 0], [1, 1, 0], [1, 1, 1]], type: :f64)
      iex> Nx.LinAlg.triangular_solve(a, Nx.tensor([1, 2, 1]))
      #Nx.Tensor<
        f64[3]
        [1.0, 1.0, -1.0]
      >

      iex> a = Nx.tensor([[1, 0, 0], [1, 1, 0], [0, 1, 1]])
      iex> b = Nx.tensor([[1, 2, 3], [2, 2, 4], [2, 0, 1]])
      iex> Nx.LinAlg.triangular_solve(a, b)
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 2.0, 3.0],
          [1.0, 0.0, 1.0],
          [1.0, 0.0, 0.0]
        ]
      >

      iex> a = Nx.tensor([[1, 1, 1, 1], [0, 1, 0, 1], [0, 0, 1, 2], [0, 0, 0, 3]])
      iex> Nx.LinAlg.triangular_solve(a, Nx.tensor([2, 4, 2, 4]), lower: false)
      #Nx.Tensor<
        f32[4]
        [-1.3333333730697632, 2.6666667461395264, -0.6666666865348816, 1.3333333730697632]
      >

      iex> a = Nx.tensor([[1, 0, 0], [1, 1, 0], [1, 2, 1]])
      iex> b = Nx.tensor([[0, 2, 1], [1, 1, 0], [3, 3, 1]])
      iex> Nx.LinAlg.triangular_solve(a, b, left_side: false)
      #Nx.Tensor<
        f32[3][3]
        [
          [-1.0, 0.0, 1.0],
          [0.0, 1.0, 0.0],
          [1.0, 1.0, 1.0]
        ]
      >

      iex> a = Nx.tensor([[1, 1, 1], [0, 1, 1], [0, 0, 1]], type: :f64)
      iex> Nx.LinAlg.triangular_solve(a, Nx.tensor([1, 2, 1]), transform_a: :transpose, lower: false)
      #Nx.Tensor<
        f64[3]
        [1.0, 1.0, -1.0]
      >

      iex> a = Nx.tensor([[1, 0, 0], [1, 1, 0], [1, 1, 1]], type: :f64)
      iex> Nx.LinAlg.triangular_solve(a, Nx.tensor([1, 2, 1]), transform_a: :none)
      #Nx.Tensor<
        f64[3]
        [1.0, 1.0, -1.0]
      >

      iex> a = Nx.tensor([[1, 0, 0], [1, 1, 0], [1, 2, 1]])
      iex> b = Nx.tensor([[0, 1, 3], [2, 1, 3]])
      iex> Nx.LinAlg.triangular_solve(a, b, left_side: false)
      #Nx.Tensor<
        f32[2][3]
        [
          [2.0, -5.0, 3.0],
          [4.0, -5.0, 3.0]
        ]
      >

      iex> a = Nx.tensor([[1, 0, 0], [1, 1, 0], [1, 2, 1]])
      iex> b = Nx.tensor([[0, 2], [3, 0], [0, 0]])
      iex> Nx.LinAlg.triangular_solve(a, b, left_side: true)
      #Nx.Tensor<
        f32[3][2]
        [
          [0.0, 2.0],
          [3.0, -2.0],
          [-6.0, 2.0]
        ]
      >

      iex> a = Nx.tensor([
      ...> [1, 0, 0],
      ...> [1, Complex.new(0, 1), 0],
      ...> [Complex.new(0, 1), 1, 1]
      ...>])
      iex> b = Nx.tensor([1, -1, Complex.new(3, 3)])
      iex> Nx.LinAlg.triangular_solve(a, b)
      #Nx.Tensor<
        c64[3]
        [1.0+0.0i, 0.0+2.0i, 3.0+0.0i]
      >

      iex> a = Nx.tensor([[[1, 0], [2, 3]], [[4, 0], [5, 6]]])
      iex> b = Nx.tensor([[2, -1], [3, 7]])
      iex> Nx.LinAlg.triangular_solve(a, b)
      #Nx.Tensor<
        f32[2][2]
        [
          [2.0, -1.6666666269302368],
          [0.75, 0.5416666865348816]
        ]
      >

  ### Error cases

      iex> Nx.LinAlg.triangular_solve(Nx.tensor([[3, 0, 0, 0], [2, 1, 0, 0]]), Nx.tensor([4, 2, 4, 2]))
      ** (ArgumentError) triangular_solve/3 expected a square matrix or a batch of square matrices, got tensor with shape: {2, 4}

      iex> Nx.LinAlg.triangular_solve(Nx.tensor([[3, 0, 0, 0], [2, 1, 0, 0], [1, 1, 1, 1], [1, 1, 1, 1]]), Nx.tensor([4]))
      ** (ArgumentError) incompatible dimensions for a and b on triangular solve

      iex> Nx.LinAlg.triangular_solve(Nx.tensor([[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [1, 1, 1, 1]]), Nx.tensor([4, 2, 4, 2]))
      ** (ArgumentError) can't solve for singular matrix

      iex> a = Nx.tensor([[1, 0, 0], [1, 1, 0], [1, 1, 1]], type: :f64)
      iex> Nx.LinAlg.triangular_solve(a, Nx.tensor([1, 2, 1]), transform_a: :conjugate)
      ** (ArgumentError) complex numbers not supported yet

      iex> a = Nx.tensor([[1, 0, 0], [1, 1, 0], [1, 1, 1]], type: :f64)
      iex> Nx.LinAlg.triangular_solve(a, Nx.tensor([1, 2, 1]), transform_a: :other)
      ** (ArgumentError) invalid value for :transform_a option, expected :none, :transpose, or :conjugate, got: :other

  """
  def triangular_solve(a, b, opts \\ []) do
    opts = keyword!(opts, lower: true, left_side: true, transform_a: :none)
    output_type = binary_type(a, b) |> Nx.Type.to_floating()
    %T{shape: a_shape} = a = Nx.to_tensor(a)
    %T{shape: b_shape} = b = Nx.to_tensor(b)

    case opts[:transform_a] do
      t when t in [:none, :transpose] ->
        nil

      :conjugate ->
        raise ArgumentError, "complex numbers not supported yet"

      t ->
        raise ArgumentError,
              "invalid value for :transform_a option, expected :none, :transpose, or :conjugate, " <>
                "got: #{inspect(t)}"
    end

    :ok = Nx.Shape.triangular_solve(a_shape, b_shape, opts[:left_side])

    impl!(a, b).triangular_solve(%{b | type: output_type}, a, b, opts)
  end

  @doc """
  Solves the system `AX = B`.

  `A` must have shape `{..., n, n}` and `B` must have shape `{..., n, m}` or `{..., n}`.
  `X` has the same shape as `B`.

  ## Examples

      iex> a = Nx.tensor([[1, 3, 2, 1], [2, 1, 0, 0], [1, 0, 1, 0], [1, 1, 1, 1]])
      iex> Nx.LinAlg.solve(a, Nx.tensor([-3, 0, 4, -2])) |> Nx.round()
      #Nx.Tensor<
        f32[4]
        [1.0, -2.0, 3.0, -4.0]
      >

      iex> a = Nx.tensor([[1, 0, 1], [1, 1, 0], [1, 1, 1]], type: :f64)
      iex> Nx.LinAlg.solve(a, Nx.tensor([0, 2, 1])) |> Nx.round()
      #Nx.Tensor<
        f64[3]
        [1.0, 1.0, -1.0]
      >

      iex> a = Nx.tensor([[1, 0, 1], [1, 1, 0], [0, 1, 1]])
      iex> b = Nx.tensor([[2, 2, 3], [2, 2, 4], [2, 0, 1]])
      iex> Nx.LinAlg.solve(a, b) |> Nx.round()
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 2.0, 3.0],
          [1.0, 0.0, 1.0],
          [1.0, 0.0, 0.0]
        ]
      >

      iex> a = Nx.tensor([[[14, 10], [9, 9]], [[4, 11], [2, 3]]])
      iex> b = Nx.tensor([[[2, 4], [3, 2]], [[1, 5], [-3, -1]]])
      iex> Nx.LinAlg.solve(a, b) |> Nx.round()
      #Nx.Tensor<
        f32[2][2][2]
        [
          [
            [0.0, 0.0],
            [1.0, 0.0]
          ],
          [
            [-4.0, -3.0],
            [1.0, 1.0]
          ]
        ]
      >

  If the axes are named, their names are not preserved in the output:

      iex> a = Nx.tensor([[1, 0, 1], [1, 1, 0], [1, 1, 1]], names: [:x, :y])
      iex> Nx.LinAlg.solve(a, Nx.tensor([0, 2, 1], names: [:z])) |> Nx.round()
      #Nx.Tensor<
        f32[3]
        [1.0, 1.0, -1.0]
      >

  ### Error cases

      iex> Nx.LinAlg.solve(Nx.tensor([[1, 0], [0, 1]]), Nx.tensor([4, 2, 4, 2]))
      ** (ArgumentError) `b` tensor has incompatible dimensions, expected {2, 2} or {2}, got: {4}

      iex> Nx.LinAlg.solve(Nx.tensor([[3, 0, 0, 0], [2, 1, 0, 0], [1, 1, 1, 1]]), Nx.tensor([4]))
      ** (ArgumentError) `a` tensor has incompatible dimensions, expected a square matrix or a batch of square matrices, got: {3, 4}
  """
  # IMPORTANT: This function cannot be a defn because
  # optional needs to work on the actual backend.
  @doc from_backend: false
  def solve(a, b) do
    %T{shape: a_shape, type: a_type} = a = Nx.to_tensor(a)
    %T{shape: b_shape, type: b_type} = b = Nx.to_tensor(b)

    output_shape = Nx.Shape.solve(a_shape, b_shape)
    output_type = a_type |> Nx.Type.merge(b_type) |> Nx.Type.to_floating()
    output = Nx.template(output_shape, output_type)

    Nx.Shared.optional(:solve, [a, b], output, fn a, b ->
      # Since we have triangular solve, which accepts upper
      # triangular matrices with the `lower: false` option,
      # we can solve a system as follows:

      # A.X = B -> QR.X = B -> R.X = adjoint(Q).B

      {q, r} = Nx.LinAlg.qr(a)
      q_rank = Nx.rank(q)
      batches = Enum.to_list(0..(q_rank - 3)//1)
      qb = Nx.dot(adjoint(q), [q_rank - 1], batches, b, [q_rank - 2], batches)
      triangular_solve(r, qb, lower: false)
    end)
  end

  @doc """
  Inverts a batch of square matrices.

  For non-square matrices, use `svd/2` for pseudo-inverse calculations.

  ## Examples

      iex> a = Nx.tensor([[1, 2, 1, 1], [0, 1, 0, 1], [0, 0, 1, 1], [0 , 0, 0, 1]])
      iex> a_inv = Nx.LinAlg.invert(a)
      #Nx.Tensor<
        f32[4][4]
        [
          [1.0, -2.0, -1.0, 2.0],
          [0.0, 1.0, 0.0, -1.0],
          [0.0, 0.0, 1.0, -1.0],
          [0.0, 0.0, 0.0, 1.0]
        ]
      >
      iex> Nx.dot(a, a_inv)
      #Nx.Tensor<
        f32[4][4]
        [
          [1.0, 0.0, 0.0, 0.0],
          [0.0, 1.0, 0.0, 0.0],
          [0.0, 0.0, 1.0, 0.0],
          [0.0, 0.0, 0.0, 1.0]
        ]
      >
      iex> Nx.dot(a_inv, a)
      #Nx.Tensor<
        f32[4][4]
        [
          [1.0, 0.0, 0.0, 0.0],
          [0.0, 1.0, 0.0, 0.0],
          [0.0, 0.0, 1.0, 0.0],
          [0.0, 0.0, 0.0, 1.0]
        ]
      >

      iex> a = Nx.tensor([[[1, 2], [0, 1]], [[1, 1], [0, 1]]])
      iex> a_inv = Nx.LinAlg.invert(a)
      #Nx.Tensor<
        f32[2][2][2]
        [
          [
            [1.0, -2.0],
            [0.0, 1.0]
          ],
          [
            [1.0, -1.0],
            [0.0, 1.0]
          ]
        ]
      >
      iex> Nx.dot(a, [2], [0], a_inv, [1], [0])
      #Nx.Tensor<
        f32[2][2][2]
        [
          [
            [1.0, 0.0],
            [0.0, 1.0]
          ],
          [
            [1.0, 0.0],
            [0.0, 1.0]
          ]
        ]
      >
      iex> Nx.dot(a_inv, [2], [0], a, [1], [0])
      #Nx.Tensor<
        f32[2][2][2]
        [
          [
            [1.0, 0.0],
            [0.0, 1.0]
          ],
          [
            [1.0, 0.0],
            [0.0, 1.0]
          ]
        ]
      >

  ### Error cases

      iex> Nx.LinAlg.invert(Nx.tensor([[3, 0, 0, 0], [2, 1, 0, 0]]))
      ** (ArgumentError) invert/1 expects a square matrix or a batch of square matrices, got tensor with shape: {2, 4}

      iex> Nx.LinAlg.invert(Nx.tensor([[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [1, 1, 1, 1]]))
      ** (ArgumentError) can't solve for singular matrix

  """
  @doc from_backend: false
  defn invert(tensor) do
    ans =
      tensor
      |> invert_shape()
      |> invert_tensor()

    custom_grad(ans, [tensor], fn g ->
      # As defined in https://juliadiff.org/ChainRulesCore.jl/stable/maths/arrays.html#Matrix-inversion-2
      ans_h = adjoint(ans)
      [{tensor, ans_h |> Nx.negate() |> Nx.dot(g) |> Nx.dot(ans_h)}]
    end)
  end

  defnp invert_tensor(tensor) do
    n = elem(Nx.shape(tensor), Nx.rank(tensor) - 1)
    identity = Nx.broadcast(Nx.eye(n), Nx.shape(tensor))
    Nx.LinAlg.solve(tensor, identity)
  end

  deftransformp invert_shape(tensor) do
    shape = Nx.shape(tensor)

    shape
    |> Tuple.to_list()
    |> Enum.split(-2)
    |> case do
      {_, [n, n]} ->
        tensor

      _ ->
        raise ArgumentError,
              "invert/1 expects a square matrix or a batch of square matrices, got tensor with shape: #{inspect(shape)}"
    end
  end

  @doc """
  Calculates the QR decomposition of a tensor with shape `{..., M, N}`.

  ## Options

    * `:mode` - Can be one of `:reduced`, `:complete`. Defaults to `:reduced`
      For the following, `K = min(M, N)`

      * `:reduced` - returns `q` and `r` with shapes `{..., M, K}` and `{..., K, N}`
      * `:complete` - returns `q` and `r` with shapes `{..., M, M}` and `{..., M, N}`

    * `:eps` - Rounding error threshold that can be applied during the triangularization. Defaults to `1.0e-10`

  ## Examples

      iex> {q, r} = Nx.LinAlg.qr(Nx.tensor([[-3, 2, 1], [0, 1, 1], [0, 0, -1]]))
      iex> q
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 1.0]
        ]
      >
      iex> r
      #Nx.Tensor<
        f32[3][3]
        [
          [-3.0, 2.0, 1.0],
          [0.0, 1.0, 1.0],
          [0.0, 0.0, -1.0]
        ]
      >

      iex> t = Nx.tensor([[3, 2, 1], [0, 1, 1], [0, 0, 1]])
      iex> {q, r} = Nx.LinAlg.qr(t)
      iex> q
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 1.0]
        ]
      >
      iex> r
      #Nx.Tensor<
        f32[3][3]
        [
          [3.0, 2.0, 1.0],
          [0.0, 1.0, 1.0],
          [0.0, 0.0, 1.0]
        ]
      >

      iex> {qs, rs} = Nx.LinAlg.qr(Nx.tensor([[[-3, 2, 1], [0, 1, 1], [0, 0, -1]],[[3, 2, 1], [0, 1, 1], [0, 0, 1]]]))
      iex> qs
      #Nx.Tensor<
        f32[2][3][3]
        [
          [
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0]
          ],
          [
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0]
          ]
        ]
      >
      iex> rs
      #Nx.Tensor<
        f32[2][3][3]
        [
          [
            [-3.0, 2.0, 1.0],
            [0.0, 1.0, 1.0],
            [0.0, 0.0, -1.0]
          ],
          [
            [3.0, 2.0, 1.0],
            [0.0, 1.0, 1.0],
            [0.0, 0.0, 1.0]
          ]
        ]
      >

      iex> t = Nx.tensor([[3, 2, 1], [0, 1, 1], [0, 0, 1], [0, 0, 1]], type: :f32)
      iex> {q, r} = Nx.LinAlg.qr(t, mode: :reduced)
      iex> q
      #Nx.Tensor<
        f32[4][3]
        [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 0.7071067690849304],
          [0.0, 0.0, 0.7071067690849304]
        ]
      >
      iex> r
      #Nx.Tensor<
        f32[3][3]
        [
          [3.0, 2.0, 1.0],
          [0.0, 1.0, 1.0],
          [0.0, 0.0, 1.4142135381698608]
        ]
      >

      iex> t = Nx.tensor([[3, 2, 1], [0, 1, 1], [0, 0, 1], [0, 0, 0]], type: :f32)
      iex> {q, r} = Nx.LinAlg.qr(t, mode: :complete)
      iex> q
      #Nx.Tensor<
        f32[4][4]
        [
          [1.0, 0.0, 0.0, 0.0],
          [0.0, 1.0, 0.0, 0.0],
          [0.0, 0.0, 1.0, 0.0],
          [0.0, 0.0, 0.0, 1.0]
        ]
      >
      iex> r
      #Nx.Tensor<
        f32[4][3]
        [
          [3.0, 2.0, 1.0],
          [0.0, 1.0, 1.0],
          [0.0, 0.0, 1.0],
          [0.0, 0.0, 0.0]
        ]
      >

  ## Error cases

      iex> Nx.LinAlg.qr(Nx.tensor([[[1, 1, 1, 1], [-1, 4, 4, -1], [4, -2, 2, 0]]]))
      ** (ArgumentError) tensor must have at least as many rows as columns in the last two axes, got 3 rows and 4 columns

      iex> Nx.LinAlg.qr(Nx.tensor([1, 2, 3, 4, 5]))
      ** (ArgumentError) tensor must have at least rank 2, got rank 1 with shape {5}
  """
  def qr(tensor, opts \\ []) do
    opts = keyword!(opts, mode: :reduced, eps: 1.0e-10)
    %T{type: type, shape: shape} = tensor = Nx.to_tensor(tensor)

    mode = opts[:mode]
    valid_modes = [:reduced, :complete]

    unless mode in valid_modes do
      raise ArgumentError,
            "invalid :mode received. Expected one of #{valid_modes}, received: #{mode}"
    end

    output_type = Nx.Type.to_floating(type)
    {q_shape, r_shape} = Nx.Shape.qr(shape, opts)

    impl!(tensor).qr(
      {%{
         tensor
         | type: output_type,
           shape: q_shape,
           names: List.duplicate(nil, tuple_size(q_shape))
       },
       %{
         tensor
         | type: output_type,
           shape: r_shape,
           names: List.duplicate(nil, tuple_size(r_shape))
       }},
      tensor,
      opts
    )
  end

  @doc """
  Calculates the Moore-Penrose inverse, or the pseudoinverse, of a matrix.

  ## Options
    * `:eps` - Rounding error threshold used to assume values as 0. Defaults to `1.0e-10`

  ## Examples

  Scalar case:

      iex> Nx.LinAlg.pinv(2)
      #Nx.Tensor<
        f32
        0.5
      >

      iex> Nx.LinAlg.pinv(0)
      #Nx.Tensor<
        f32
        0.0
      >

  Vector case:

      iex> Nx.LinAlg.pinv(Nx.tensor([0, 1, 2]))
      #Nx.Tensor<
        f32[3]
        [0.0, 0.20000000298023224, 0.4000000059604645]
      >

      iex> Nx.LinAlg.pinv(Nx.tensor([0, 0, 0]))
      #Nx.Tensor<
        f32[3]
        [0.0, 0.0, 0.0]
      >

  Matrix case:

      iex> Nx.LinAlg.pinv(Nx.tensor([[1, 1], [3, 4]]))
      #Nx.Tensor<
        f32[2][2]
        [
          [3.9924840927124023, -1.0052788257598877],
          [-3.005120038986206, 1.0071183443069458]
        ]
      >

      iex> Nx.LinAlg.pinv(Nx.tensor([[0.5, 0], [0, 1], [0.5, 0]]))
      #Nx.Tensor<
        f32[2][3]
        [
          [0.9999999403953552, 0.0, 0.9999999403953552],
          [0.0, 1.0, 0.0]
        ]
      >
  """
  defn pinv(tensor, opts \\ []) do
    opts = keyword!(opts, eps: 1.0e-10)

    if Nx.all(Nx.abs(tensor) <= opts[:eps]) do
      pinv_zero(tensor)
    else
      pinv_non_zero(tensor, opts)
    end
  end

  defnp pinv_zero(tensor) do
    # the tensor is already zero and the pseudo-inverse
    # is defined to be zero in this case
    0
    |> Nx.tensor(type: Nx.type(tensor))
    |> Nx.broadcast(pinv_zero_shape(tensor))
  end

  deftransformp pinv_zero_shape(tensor) do
    shape = Nx.shape(tensor)
    rank = tuple_size(shape)

    if rank < 2 do
      shape
    else
      [n, m | tl] =
        shape
        |> Tuple.to_list()
        |> Enum.reverse()

      tl
      |> List.to_tuple()
      |> Tuple.insert_at(rank - 2, n)
      |> Tuple.insert_at(rank - 1, m)
    end
  end

  defnp pinv_non_zero(tensor, opts \\ []) do
    case Nx.rank(tensor) do
      0 ->
        1 / tensor

      1 ->
        adjoint(tensor) / norm(tensor) ** 2

      _ ->
        {u, s, vt} = Nx.LinAlg.svd(tensor)
        v = adjoint(vt)
        ut = adjoint(u)

        s_idx = Nx.abs(s) < opts[:eps]
        adjusted_s = Nx.select(s_idx, 1, s)
        s_shape = {Nx.axis_size(v, -1), Nx.axis_size(ut, -2)}

        s_inv_matrix =
          Nx.broadcast(0, s_shape)
          |> Nx.put_diagonal(Nx.select(s_idx, 0, 1 / adjusted_s))

        v |> Nx.dot(s_inv_matrix) |> Nx.dot(ut)
    end
  end

  @doc """
  Calculates the Eigenvalues and Eigenvectors of batched Hermitian 2-D matrices.

  It returns `{eigenvals, eigenvecs}`.

  ## Options

    * `:max_iter` - `integer`. Defaults to `1_000`
      Number of maximum iterations before stopping the decomposition

    * `:eps` - `float`. Defaults to 1.0e-4
      Tolerance applied during the decomposition

  Note not all options apply to all backends, as backends may have
  specific optimizations that render these mechanisms unnecessary.

  ## Examples

      iex> {eigenvals, eigenvecs} = Nx.LinAlg.eigh(Nx.tensor([[1, 0], [0, 2]]))
      iex> Nx.round(eigenvals)
      #Nx.Tensor<
        f32[2]
        [1.0, 2.0]
      >
      iex> eigenvecs
      #Nx.Tensor<
        f32[2][2]
        [
          [1.0, 0.0],
          [0.0, 1.0]
        ]
      >

      iex> {eigenvals, eigenvecs} = Nx.LinAlg.eigh(Nx.tensor([[0, 1, 2], [1, 0, 2], [2, 2, 3]]))
      iex> Nx.round(eigenvals)
      #Nx.Tensor<
        f32[3]
        [5.0, -1.0, -1.0]
      >
      iex> eigenvecs
      #Nx.Tensor<
        f32[3][3]
        [
          [0.4075949788093567, 0.9131628274917603, 0.0],
          [0.40837883949279785, -0.18228201568126678, 0.8944271802902222],
          [0.8167576789855957, -0.36456403136253357, -0.4472135901451111]
        ]
      >

      iex> {eigenvals, eigenvecs} = Nx.LinAlg.eigh(Nx.tensor([[[2, 5],[5, 6]], [[1, 0], [0, 4]]]))
      iex> Nx.round(eigenvals)
      #Nx.Tensor<
        f32[2][2]
        [
          [9.0, -1.0],
          [1.0, 4.0]
        ]
      >
      iex> eigenvecs
      #Nx.Tensor<
        f32[2][2][2]
        [
          [
            [0.5612090229988098, -0.8276740908622742],
            [0.8276740908622742, 0.5612090229988098]
          ],
          [
            [1.0, 0.0],
            [0.0, 1.0]
          ]
        ]
      >

  ## Error cases

      iex> Nx.LinAlg.eigh(Nx.tensor([[1, 2, 3], [4, 5, 6]]))
      ** (ArgumentError) tensor must be a square matrix or a batch of square matrices, got shape: {2, 3}

      iex> Nx.LinAlg.eigh(Nx.tensor([[1, 2], [3, 4]]))
      ** (ArgumentError) matrix must be hermitian, a matrix is hermitian iff X = adjoint(X)
  """
  def eigh(tensor, opts \\ []) do
    opts = keyword!(opts, max_iter: 1_000, eps: 1.0e-4)
    %T{type: type, shape: shape} = tensor = Nx.to_tensor(tensor)

    output_type = Nx.Type.to_floating(type)

    {eigenvals_shape, eigenvecs_shape} = Nx.Shape.eigh(shape)
    rank = tuple_size(shape)

    eigenvecs_name = List.duplicate(nil, rank)
    eigenvals_name = tl(eigenvecs_name)

    impl!(tensor).eigh(
      {%{tensor | names: eigenvals_name, type: output_type, shape: eigenvals_shape},
       %{tensor | names: eigenvecs_name, type: output_type, shape: eigenvecs_shape}},
      tensor,
      opts
    )
  end

  @doc """
  Calculates the Singular Value Decomposition of batched 2-D matrices.

  It returns `{u, s, vt}` where the elements of `s` are sorted
  from highest to lowest.

  ## Options

    * `:max_iter` - `integer`. Defaults to `100`
      Number of maximum iterations before stopping the decomposition

  Note not all options apply to all backends, as backends may have
  specific optimizations that render these mechanisms unnecessary.

  ## Examples

      iex> {u, s, vt} = Nx.LinAlg.svd(Nx.tensor([[1, 0, 0], [0, 1, 0], [0, 0, -1]]))
      iex> u
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, -1.0]
        ]
      >
      iex> s
      #Nx.Tensor<
        f32[3]
        [1.0, 1.0, 1.0]
      >
      iex> vt
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 1.0]
        ]
      >

      iex> {u, s, vt} = Nx.LinAlg.svd(Nx.tensor([[2, 0, 0], [0, 3, 0], [0, 0, -1], [0, 0, 0]]))
      iex> u
      #Nx.Tensor<
        f32[4][4]
        [
          [0.0, 0.9999999403953552, 0.0, 0.0],
          [1.0, 0.0, 0.0, 0.0],
          [0.0, 0.0, -1.0, 0.0],
          [0.0, 0.0, 0.0, 1.0]
        ]
      >
      iex> s
      #Nx.Tensor<
        f32[3]
        [3.0, 1.9999998807907104, 1.0]
      >
      iex> vt
      #Nx.Tensor<
        f32[3][3]
        [
          [0.0, 1.0, 0.0],
          [1.0, 0.0, 0.0],
          [0.0, 0.0, 1.0]
        ]
      >

  """
  def svd(tensor, opts \\ []) do
    opts = keyword!(opts, max_iter: 100)
    %T{type: type, shape: shape} = tensor = Nx.to_tensor(tensor)

    Nx.Shared.raise_complex_not_implemented_yet(type, "LinAlg.svd", 2)

    output_type = Nx.Type.to_floating(type)
    {u_shape, s_shape, v_shape} = Nx.Shape.svd(shape)
    rank = tuple_size(shape)

    output =
      {%{tensor | names: List.duplicate(nil, rank), type: output_type, shape: u_shape},
       %{tensor | names: List.duplicate(nil, rank - 1), type: output_type, shape: s_shape},
       %{tensor | names: List.duplicate(nil, rank), type: output_type, shape: v_shape}}

    Nx.Shared.optional(:svd, [tensor, opts], output, &Nx.LinAlg.SVD.svd/2)
  end

  @doc """
  Calculates the A = PLU decomposition of batched square 2-D matrices A.

  ## Options

    * `:eps` - Rounding error threshold that can be applied during the factorization

  ## Examples

      iex> {p, l, u} = Nx.LinAlg.lu(Nx.tensor([[1, 2, 3], [4, 5, 6], [7, 8, 9]]))
      iex> p
      #Nx.Tensor<
        s64[3][3]
        [
          [0, 0, 1],
          [0, 1, 0],
          [1, 0, 0]
        ]
      >
      iex> l
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 0.0, 0.0],
          [0.5714285969734192, 1.0, 0.0],
          [0.1428571492433548, 2.0, 1.0]
        ]
      >
      iex> u
      #Nx.Tensor<
        f32[3][3]
        [
          [7.0, 8.0, 9.0],
          [0.0, 0.4285714328289032, 0.8571428656578064],
          [0.0, 0.0, 0.0]
        ]
      >
      iex> p |> Nx.dot(l) |> Nx.dot(u)
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 2.0, 3.0],
          [4.0, 5.0, 6.0],
          [7.0, 8.0, 9.0]
        ]
      >

      iex> {p, l, u} = Nx.LinAlg.lu(Nx.tensor([[1, 0, 1], [-1, 0, -1], [1, 1, 1]]))
      iex> p
      #Nx.Tensor<
        s64[3][3]
        [
          [1, 0, 0],
          [0, 0, 1],
          [0, 1, 0]
        ]
      >
      iex> l
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 0.0, 0.0],
          [1.0, 1.0, 0.0],
          [-1.0, 0.0, 1.0]
        ]
      >
      iex> u
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 0.0, 1.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 0.0]
        ]
      >
      iex> p |> Nx.dot(l) |> Nx.dot(u)
      #Nx.Tensor<
        f32[3][3]
        [
          [1.0, 0.0, 1.0],
          [-1.0, 0.0, -1.0],
          [1.0, 1.0, 1.0]
        ]
      >

      iex> {p, l, u} = Nx.LinAlg.lu(Nx.tensor([[[9, 8, 7], [6, 5, 4], [3, 2, 1]], [[-1, 0, -1], [1, 0, 1], [1, 1, 1]]]))
      iex> p
      #Nx.Tensor<
        s64[2][3][3]
        [
          [
            [1, 0, 0],
            [0, 1, 0],
            [0, 0, 1]
          ],
          [
            [1, 0, 0],
            [0, 0, 1],
            [0, 1, 0]
          ]
        ]
      >
      iex> l
      #Nx.Tensor<
        f32[2][3][3]
        [
          [
            [1.0, 0.0, 0.0],
            [0.6666666865348816, 1.0, 0.0],
            [0.3333333432674408, 2.0, 1.0]
          ],
          [
            [1.0, 0.0, 0.0],
            [-1.0, 1.0, 0.0],
            [-1.0, 0.0, 1.0]
          ]
        ]
      >
      iex> u
      #Nx.Tensor<
        f32[2][3][3]
        [
          [
            [9.0, 8.0, 7.0],
            [0.0, -0.3333333432674408, -0.6666666865348816],
            [0.0, 0.0, 0.0]
          ],
          [
            [-1.0, 0.0, -1.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0]
          ]
        ]
      >
      iex> p |> Nx.dot([2], [0], l, [1], [0]) |> Nx.dot([2], [0], u, [1], [0])
      #Nx.Tensor<
        f32[2][3][3]
        [
          [
            [9.0, 8.0, 7.0],
            [6.0, 5.0, 4.0],
            [3.0, 2.0, 1.0]
          ],
          [
            [-1.0, 0.0, -1.0],
            [1.0, 0.0, 1.0],
            [1.0, 1.0, 1.0]
          ]
        ]
      >

  ## Error cases

      iex> Nx.LinAlg.lu(Nx.tensor([[1, 1, 1, 1], [-1, 4, 4, -1], [4, -2, 2, 0]]))
      ** (ArgumentError) tensor must be a square matrix or a batch of square matrices, got shape: {3, 4}
  """
  def lu(tensor, opts \\ []) do
    opts = keyword!(opts, eps: 1.0e-10)
    %T{type: type, shape: shape} = tensor = Nx.to_tensor(tensor)

    output_type = Nx.Type.to_floating(type)
    {p_shape, l_shape, u_shape} = Nx.Shape.lu(shape)
    names = List.duplicate(nil, tuple_size(shape))

    impl!(tensor).lu(
      {%{tensor | type: type, shape: p_shape, names: names},
       %{tensor | type: output_type, shape: l_shape, names: names},
       %{tensor | type: output_type, shape: u_shape, names: names}},
      tensor,
      opts
    )
  end

  @doc """
  Produces the tensor taken to the given power by matrix dot-product.

  The input is always a tensor of batched square matrices and an integer,
  and the output is a tensor of the same dimensions as the input tensor.

  The dot-products are unrolled inside `defn`.

  ## Examples

      iex> Nx.LinAlg.matrix_power(Nx.tensor([[1, 2], [3, 4]]), 0)
      #Nx.Tensor<
        s64[2][2]
        [
          [1, 0],
          [0, 1]
        ]
      >

      iex> Nx.LinAlg.matrix_power(Nx.tensor([[1, 2], [3, 4]]), 6)
      #Nx.Tensor<
        s64[2][2]
        [
          [5743, 8370],
          [12555, 18298]
        ]
      >

      iex> Nx.LinAlg.matrix_power(Nx.eye(3), 65535)
      #Nx.Tensor<
        s64[3][3]
        [
          [1, 0, 0],
          [0, 1, 0],
          [0, 0, 1]
        ]
      >

      iex> Nx.LinAlg.matrix_power(Nx.tensor([[1, 2], [3, 4]]), -1)
      #Nx.Tensor<
        f32[2][2]
        [
          [-2.0, 1.0],
          [1.5, -0.5]
        ]
      >

      iex> Nx.LinAlg.matrix_power(Nx.iota({2, 2, 2}), 3)
      #Nx.Tensor<
        s64[2][2][2]
        [
          [
            [6, 11],
            [22, 39]
          ],
          [
            [514, 615],
            [738, 883]
          ]
        ]
      >

      iex> Nx.LinAlg.matrix_power(Nx.iota({2, 2, 2}), -3)
      #Nx.Tensor<
        f32[2][2][2]
        [
          [
            [-4.875, 1.375],
            [2.75, -0.75]
          ],
          [
            [-110.375, 76.875],
            [92.25, -64.25]
          ]
        ]
      >

      iex> Nx.LinAlg.matrix_power(Nx.tensor([[1, 2], [3, 4], [5, 6]]), 1)
      ** (ArgumentError) matrix_power/2 expects a square matrix or a batch of square matrices, got tensor with shape: {3, 2}
  """
  @doc from_backend: false
  def matrix_power(tensor, power) when is_integer(power) and power < 0 do
    matrix_power(invert(tensor), abs(power))
  end

  # We need a special-case for 0 since the code below
  # is optimized to not compute an initial eye.
  def matrix_power(tensor, 0) do
    shape = Nx.shape(tensor)
    :ok = Nx.Shape.matrix_power(shape)

    Nx.eye(shape)
  end

  def matrix_power(tensor, power) when is_integer(power) do
    shape = Nx.shape(tensor)
    :ok = Nx.Shape.matrix_power(shape)

    rank = Nx.rank(tensor)
    batches = Enum.to_list(0..(rank - 3)//1)
    dot_product = &Nx.dot(&1, [rank - 1], batches, &2, [rank - 2], batches)

    power
    |> Integer.digits(2)
    |> tl()
    |> Enum.reverse()
    |> Enum.reduce({nil, tensor}, fn
      1, {nil, exp_tensor} ->
        {exp_tensor, dot_product.(exp_tensor, exp_tensor)}

      1, {result_tensor, exp_tensor} ->
        {dot_product.(result_tensor, exp_tensor), dot_product.(exp_tensor, exp_tensor)}

      0, {result_tensor, exp_tensor} ->
        {result_tensor, dot_product.(exp_tensor, exp_tensor)}
    end)
    |> then(fn
      {nil, exp_tensor} -> exp_tensor
      {result, exp_tensor} -> dot_product.(result, exp_tensor)
    end)
  end

  @doc """
  Calculates the determinant of batched square matrices.

  ### Examples

  For 2x2 and 3x3, the results are given by the closed formulas:

      iex> Nx.LinAlg.determinant(Nx.tensor([[1, 2], [3, 4]]))
      #Nx.Tensor<
        f32
        -2.0
      >

      iex> Nx.LinAlg.determinant(Nx.tensor([[1.0, 2.0, 3.0], [1.0, -2.0, 3.0], [7.0, 8.0, 9.0]]))
      #Nx.Tensor<
        f32
        48.0
      >

  When there are linearly dependent rows or columns, the determinant is 0:

      iex> Nx.LinAlg.determinant(Nx.tensor([[1.0, 0.0], [3.0, 0.0]]))
      #Nx.Tensor<
        f32
        0.0
      >

      iex> Nx.LinAlg.determinant(Nx.tensor([[1.0, 2.0, 3.0], [-1.0, -2.0, -3.0], [4.0, 5.0, 6.0]]))
      #Nx.Tensor<
        f32
        0.0
      >

  The determinant can also be calculated when the axes are bigger than 3:

      iex> Nx.LinAlg.determinant(Nx.tensor([
      ...> [1, 0, 0, 0],
      ...> [0, 1, 2, 3],
      ...> [0, 1, -2, 3],
      ...> [0, 7, 8, 9.0]
      ...> ]))
      #Nx.Tensor<
        f32
        48.0
      >

      iex> Nx.LinAlg.determinant(Nx.tensor([
      ...> [0, 0, 0, 0, -1],
      ...> [0, 1, 2, 3, 0],
      ...> [0, 1, -2, 3, 0],
      ...> [0, 7, 8, 9, 0],
      ...> [1, 0, 0, 0, 0]
      ...> ]))
      #Nx.Tensor<
        f32
        48.0
      >

      iex> Nx.LinAlg.determinant(Nx.tensor([
      ...> [[2, 4, 6, 7], [5, 1, 8, 8], [1, 7, 3, 1], [3, 9, 2, 4]],
      ...> [[2, 5, 1, 3], [4, 1, 7, 9], [6, 8, 3, 2], [7, 8, 1, 4]]
      ...> ]))
      #Nx.Tensor<
        f32[2]
        [630.0, 630.0]
      >

  If the axes are named, their names are not preserved in the output:

      iex> two_by_two = Nx.tensor([[1, 2], [3, 4]], names: [:x, :y])
      iex> Nx.LinAlg.determinant(two_by_two)
      #Nx.Tensor<
        f32
        -2.0
      >

      iex> three_by_three = Nx.tensor([[1.0, 2.0, 3.0], [1.0, -2.0, 3.0], [7.0, 8.0, 9.0]], names: [:x, :y])
      iex> Nx.LinAlg.determinant(three_by_three)
      #Nx.Tensor<
        f32
        48.0
      >

  Also supports complex inputs:

      iex> t = Nx.tensor([[1, 0, 0], [0, Complex.new(0, 2), 0], [0, 0, 3]])
      iex> Nx.LinAlg.determinant(t)
      #Nx.Tensor<
        c64
        0.0+6.0i
      >

      iex> t = Nx.tensor([[0, 0, 0, 1], [0, Complex.new(0, 2), 0, 0], [0, 0, 3, 0], [1, 0, 0, 0]])
      iex> Nx.LinAlg.determinant(t)
      #Nx.Tensor<
        c64
        0.0-6.0i
      >

  """
  # IMPORTANT: This function cannot be a defn because
  # optional needs to work on the actual backend.
  def determinant(tensor) do
    tensor = Nx.to_tensor(tensor)
    shape = Nx.shape(tensor)
    {batch_shape, matrix_shape} = shape |> Tuple.to_list() |> Enum.split(-2)
    output = Nx.template(List.to_tuple(batch_shape), Nx.Type.to_floating(tensor.type))

    case matrix_shape do
      [n, n] ->
        :ok

      shape ->
        raise ArgumentError,
              "determinant/1 expects a square tensor, got tensor with shape: #{inspect(shape)}"
    end

    Nx.Shared.optional(:determinant, [tensor], output, fn tensor ->
      case matrix_shape do
        [2, 2] ->
          determinant_2by2(tensor)

        [3, 3] ->
          determinant_3by3(tensor)

        [n, n] ->
          determinant_NbyN(tensor, batch_shape_n: List.to_tuple(batch_shape ++ [n]))
      end
    end)
  end

  defnp determinant_2by2(t) do
    t = Nx.tile(t, [1, 2])

    result = diagonal_product(t, 0) - diagonal_product(t, 1)

    # Ensure floating point result
    result * 1.0
  end

  defnp determinant_3by3(t) do
    rank = Nx.rank(t)
    pos_t = Nx.tile(t, [1, 2])

    neg_t = Nx.reverse(pos_t, axes: [rank - 1])

    result =
      diagonal_product(pos_t, 0) +
        diagonal_product(pos_t, 1) +
        diagonal_product(pos_t, 2) -
        diagonal_product(neg_t, 0) -
        diagonal_product(neg_t, 1) -
        diagonal_product(neg_t, 2)

    # Ensure floating point result
    result * 1.0
  end

  defnp determinant_NbyN(t, opts \\ []) do
    batch_shape_n = assert_keys(opts, [:batch_shape_n])[:batch_shape_n]
    rank = Nx.rank(t)
    shape = Nx.shape(t)

    # Taken from slogdet at https://github.com/google/jax/blob/a3a6afcd5b8bf3d60aba94054bb0001c0fcc50d7/jax/_src/numpy/linalg.py#L134
    {p, l, u} = Nx.LinAlg.lu(t)

    diag = Nx.multiply(Nx.take_diagonal(l), Nx.take_diagonal(u))
    is_zero = Nx.any(diag != 0, axes: [-1])

    {batch_axes, transition_bcast_axes_1, transition_bcast_axes_2} = determinant_axes(rank)

    transitions =
      p
      |> Nx.real()
      |> Nx.dot(
        [rank - 1],
        batch_axes,
        Nx.iota(batch_shape_n, axis: -1),
        [rank - 2],
        batch_axes
      )

    upper_tri_mask = Nx.iota(shape, axis: -2) |> Nx.less(Nx.iota(shape, axis: -1))

    parity =
      transitions
      |> Nx.broadcast(shape, axes: transition_bcast_axes_1)
      |> Nx.greater(Nx.broadcast(transitions, shape, axes: transition_bcast_axes_2))
      |> Nx.multiply(upper_tri_mask)
      |> Nx.sum(axes: [-2, -1])

    sign = -2 * Nx.remainder(parity, 2) + 1
    is_zero * sign * Nx.product(diag, axes: [-1])
  end

  deftransformp determinant_axes(rank) do
    batch_axes = Enum.to_list(0..(rank - 3)//1)
    transition_bcast_axes_1 = Enum.to_list(0..(rank - 2))
    transition_bcast_axes_2 = batch_axes ++ [rank - 1]
    {batch_axes, transition_bcast_axes_1, transition_bcast_axes_2}
  end

  defnp diagonal_product(t, offset) do
    rank = Nx.rank(t)

    t
    |> Nx.take_diagonal(offset: offset)
    |> Nx.product(axes: [rank - 2])
  end

  @doc """
  Return matrix rank of input M × N matrix using Singular Value Decomposition method.

  Approximate the number of linearly independent rows by calculating the number of singular values greater than `eps * max(singular values) * max(M, N)`.
  This also appears in Numerical recipes in the discussion of SVD solutions for linear least squares [1].
  [1] W. H. Press, S. A. Teukolsky, W. T. Vetterling and B. P. Flannery, “Numerical Recipes (3rd edition)”, Cambridge University Press, 2007, page 795.

  ## Options
    * `:eps` - Rounding error threshold used to assume values as 0. Defaults to `1.0e-10`

  ## Examples

      iex> Nx.LinAlg.matrix_rank(Nx.tensor([[1, 2], [3, 4]]))
      #Nx.Tensor<
        u64
        2
      >

      iex> Nx.LinAlg.matrix_rank(Nx.tensor([[1, 1, 1, 1], [1, 1, 1, 1], [1, 2, 3, 4]]))
      #Nx.Tensor<
        u64
        2
      >

      iex> Nx.LinAlg.matrix_rank(Nx.tensor([[1, 1, 1], [2, 2, 2], [8, 9, 10], [-2, 1, 5]]))
      #Nx.Tensor<
        u64
        3
      >

  ## Error cases

      iex> Nx.LinAlg.matrix_rank(Nx.tensor([1, 2, 3]))
      ** (ArgumentError) tensor must have at least rank 2, got rank 1 with shape {3}
  """
  @doc from_backend: false
  def matrix_rank(a, opts \\ []) do
    # TODO: support batching when SVD supports it too
    opts = keyword!(opts, eps: 1.0e-10)
    shape = Nx.shape(a)
    :ok = Nx.Shape.matrix_rank(shape)

    # Calculate max dimension
    {row_dim, col_dim} = shape
    max_dim = if row_dim > col_dim, do: row_dim, else: col_dim

    # Calculate max singular value
    {_u, s, _v} = svd(a)

    s_max =
      s
      |> Nx.reduce_max()
      |> Nx.to_number()

    # Set tolerance values
    tol = opts[:eps] * max_dim * s_max

    # Calculate matrix rank
    s
    |> Nx.greater(tol)
    |> Nx.sum()
  end
end
