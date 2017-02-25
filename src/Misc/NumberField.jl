import Nemo.sub!, Base.gcd
export induce_rational_reconstruction, induce_crt

if Int==Int32
  global const p_start = 2^30
else
  global const p_start = 2^60
end

################################################################################
#
# convenience ...
#
################################################################################

#CF: we have to "extend" AnticNumberField as NumberField is just defined by
#    NumberField = AnticNumberField in Nemo.
#    Possibly should be replaced by having optional 2nd arguments?
doc"""
***
  NumberField(f::fmpq_poly)

>  The number field Q[x]/f generated by f.
"""
function AnticNumberField(f::fmpq_poly)
  return NumberField(f, "_a")
end

function AnticNumberField(f::fmpz_poly, s::Symbol)
  Qx, x = PolynomialRing(QQ, string(parent(f).S))
  return NumberField(Qx(f), s)
end

function AnticNumberField(f::fmpz_poly, s::AbstractString)
  Qx, x = PolynomialRing(QQ, string(parent(f).S))
  return NumberField(Qx(f), s)
end

function AnticNumberField(f::fmpz_poly)
  Qx, x = PolynomialRing(QQ, string(parent(f).S))
  return NumberField(Qx(f))
end

################################################################################
#
#  Base case for dot products
#
################################################################################

dot(x::fmpz, y::nf_elem) = x*y

dot(x::nf_elem, y::fmpz) = x*y

################################################################################
# given a basis (an array of elements), get a linear combination with
# random integral coefficients
################################################################################
doc"""
***
  rand(b::Array{nf_elem,1}, r::UnitRange)
 
> A random linear combination of elements in b with coefficients in r
"""
function rand(b::Array{nf_elem,1}, r::UnitRange)
  length(b) == 0 && error("Array must not be empty")

  s = zero(b[1].parent)
  t = zero(b[1].parent)

  for i = 1:length(b)
    mul!(t, b[i], rand(r))
    add!(s, t, s)
  end
  return s
end

function rand!(c::nf_elem, b::Array{nf_elem,1}, r::UnitRange)
  length(b) == 0 && error("Array must not be empty")

  mul!(c, b[1], rand(r))
  t = zero(b[1].parent)

  for i = 2:length(b)
    mul!(t, b[i], rand(r))
    add!(c, t, c)
  end
  nothing
end

################################################################################
#
#  fmpq_poly with denominator 1 to fmpz_poly
#
################################################################################

#function Base.call(a::Hecke.FmpqPolyRing, b::String)
#  return a(1)
#end


function (a::FmpzPolyRing)(b::fmpq_poly) 
  (den(b) != 1) && error("denominator has to be 1")
  z = a()
  ccall((:fmpq_poly_get_numerator, :libflint), Void,
              (Ptr{fmpz_poly}, Ptr{fmpq_poly}), &z, &b)
  return z
end

doc"""
  basis(K::AnticNumberField)

> A Q-basis for K, ie. 1, x, x^2, ... as elements of K
"""
function basis(K::AnticNumberField)
  n = degree(K)
  g = gen(K);
  d = Array(typeof(g), n)
  b = K(1)
  for i = 1:n-1
    d[i] = b
    b *= g
  end
  d[n] = b
  return d
end

doc"""
  representation_mat(a::nf_elem) -> fmpz_mat

> The right regular representation of a, i.e. the matrix representing
> the multiplication by a map on the number field.
> den(a) must be one
"""
function representation_mat(a::nf_elem)
  @assert den(a) == 1
  dummy = fmpz(0)
  n = degree(a.parent)
  M = MatrixSpace(FlintZZ, n,n)()::fmpz_mat
  t = gen(a.parent)
  b = deepcopy(a)
  for i = 1:n-1
    elem_to_mat_row!(M, i, dummy, b)
    mul!(b, b, t) ## CF: should write and use mul_gen which is faster
  end
  elem_to_mat_row!(M, n, dummy, b)
  return M
end 

function basis_mat(A::Array{nf_elem, 1})
  @assert length(A) > 0
  n = length(A)
  d = degree(parent(A[1]))

  M = MatrixSpace(FlintZZ, n, d)()

  deno = one(FlintZZ)
  dummy = one(FlintZZ)

  for i in 1:n
    deno = lcm(deno, den(A[i]))
  end

  for i in 1:n
    elem_to_mat_row!(M, i, dummy, A[i])
    for j in 1:d
      M[i, j] = divexact(deno, dummy) * M[i, j]
    end
  end
  return FakeFmpqMat(M, deno)
end

function set_den!(a::nf_elem, d::fmpz)
  ccall((:nf_elem_set_den, :libflint), 
        Void, 
       (Ptr{Nemo.nf_elem}, Ptr{Nemo.fmpz}, Ptr{Nemo.AnticNumberField}), 
       &a, &d, &parent(a))
end

doc"""
***
  charpoly(a::nf_elem) -> fmpz_poly

> The characteristic polynomial of a.
"""
function charpoly(a::nf_elem)
  d = den(a)
  Zx = PolynomialRing(ZZ, string(parent(parent(a).pol).S))[1]
  f = charpoly(Zx, representation_mat(d*a))
  return f(gen(parent(f))*d)
end

doc"""
***
  minpoy(a::nf_elem) -> fmpz_poly

> The minimal polynomial of a.
"""
function minpoly(a::nf_elem)
  d = den(a)
  Zx = PolynomialRing(ZZ, string(parent(parent(a).pol).S))[1]
  f = minpoly(Zx, representation_mat(d*a))
  return f(gen(parent(f))*d)
end
###########################################################################
# modular poly gcd and helpers
###########################################################################
function inner_crt(a::fmpz, b::fmpz, up::fmpz, pq::fmpz, pq2::fmpz = fmpz(0))
  #1 = gcd(p, q) = up + vq
  # then u = modinv(p, q)
  # vq = 1-up. i is up here
  #crt: x = a (p), x = b(q) => x = avq + bup = a(1-up) + bup
  #                              = (b-a)up + a            
  if !iszero(pq2) 
    r = ((b-a)*up + a) % pq
    if r > pq2
      return r-pq
    else
      return r
    end
  else
    return ((b-a)*up + a) % pq
  end
end

function induce_inner_crt(a::nf_elem, b::nf_elem, pi::fmpz, pq::fmpz, pq2::fmpz = fmpz(0))
  c = parent(a)()
  ca = fmpz()
  cb = fmpz()
  for i=0:degree(parent(a))-1
    Nemo.num_coeff!(ca, a, i)
    Nemo.num_coeff!(cb, b, i)
    Hecke._num_setcoeff!(c, i, inner_crt(ca, cb, pi, pq, pq2))
  end
  return c
end

doc"""
  induce_crt(a::GenPoly{nf_elem}, p::fmpz, b::GenPoly{nf_elem}, q::fmpz) -> GenPoly{nf_elem}, fmpz

> Given polynomials $a$ defined modulo $p$ and $b$ modulo $q$, apply the CRT
> to all coefficients recursively.
> Implicitly assumes that $a$ and $b$ have integral coefficients (ie. no
> denominators).
"""
function induce_crt(a::GenPoly{nf_elem}, p::fmpz, b::GenPoly{nf_elem}, q::fmpz, signed::Bool = false)
  c = parent(a)()
  pi = invmod(p, q)
  mul!(pi, pi, p)
  pq = p*q
  if signed
    pq2 = div(pq, 2)
  else
    pq2 = fmpz(0)
  end
  for i=0:max(degree(a), degree(b))
    setcoeff!(c, i, induce_inner_crt(coeff(a, i), coeff(b, i), pi, pq, pq2))
  end
  return c, pq
end

doc"""
  induce_rational_reconstruction(a::GenPoly{nf_elem}, M::fmpz) -> bool, GenPoly{nf_elem}

> Apply rational reconstruction to the coefficients of $a$. Implicitly assumes
> the coefficients to be integral (no checks done)
> returns true iff this is successful for all coefficients.
"""
function induce_rational_reconstruction(a::GenPoly{nf_elem}, M::fmpz)
  b = parent(a)()
  for i=0:degree(a)
    fl, x = rational_reconstruction(coeff(a, i), M)
    if fl
      setcoeff!(b, i, x)
    else
      return false, b
    end
  end
  return true, b
end

doc"""
  gcd(a::GenPoly{nf_elem}, b::GenPoly{nf_elem}) -> GenPoly{nf_elem}

> A modular $\gcd$
"""
function gcd(a::GenPoly{nf_elem}, b::GenPoly{nf_elem})
  return gcd_modular_kronnecker(a, b)
end

function gcd_modular(a::GenPoly{nf_elem}, b::GenPoly{nf_elem})
  # naive version, kind of
  # polys should be integral
  # rat recon maybe replace by known den if poly integral (Kronnecker)
  # if not monic, scale by gcd
  # remove content?
  a = a*(1//leading_coefficient(a))
  b = b*(1//leading_coefficient(b))
  global p_start
  p = p_start
  K = base_ring(parent(a))
  @assert parent(a) == parent(b)
  g = zero(a)
  d = fmpz(1)
  while true
    p = next_prime(p)
    me = modular_init(K, p)
    fp = deepcopy(Hecke.modular_proj(a, me))  # bad!!!
    gp = Hecke.modular_proj(b, me)
    gp = [gcd(fp[i], gp[i]) for i=1:length(gp)]
    gc = Hecke.modular_lift(gp, me)
    if isone(gc)
      return parent(a)(1)
    end
    if d == 1
      g = gc
      d = fmpz(p)
    else
      if degree(gc) < degree(g)
        g = gc
        d = fmpz(p)
      elseif degree(gc) > degree(g)
        continue
      else
        g, d = induce_crt(g, d, gc, fmpz(p))
      end
    end
    fl, gg = induce_rational_reconstruction(g, d)
    if fl  # not optimal
      r = mod(a, gg)
      if iszero(r)
        r = mod(b, gg)
        if iszero(r)
          return gg
        end
      end
    end
  end
end

import Base.gcdx

#similar to gcd_modular, but avoids rational reconstruction by controlling 
#a/the denominator
function gcd_modular_kronnecker(a::GenPoly{nf_elem}, b::GenPoly{nf_elem})
  # rat recon maybe replace by known den if poly integral (Kronnecker)
  # if not monic, scale by gcd
  # remove content?
  a = a*(1//leading_coefficient(a))
  da = Base.reduce(lcm, [den(coeff(a, i)) for i=0:degree(a)])
  b = b*(1//leading_coefficient(b))
  db = Base.reduce(lcm, [den(coeff(a, i)) for i=0:degree(a)])
  d = gcd(da, db)
  a = a*da
  b = b*db
  K = base_ring(parent(a))
  fsa = evaluate(derivative(K.pol), gen(K))*d
  #now gcd(a, b)*fsa should be in the equation order...
  global p_start
  p = p_start
  K = base_ring(parent(a))
  @assert parent(a) == parent(b)
  g = zero(a)
  d = fmpz(1)
  last_g = parent(a)(0)
  while true
    p = next_prime(p)
    me = modular_init(K, p)
    fp = deepcopy(Hecke.modular_proj(a, me))  # bad!!!
    gp = Hecke.modular_proj(b, me)
    fsap = Hecke.modular_proj(fsa, me)
    gp = [fsap[i] * gcd(fp[i], gp[i]) for i=1:length(gp)]
    gc = Hecke.modular_lift(gp, me)
    if isone(gc)
      return parent(a)(1)
    end
    if d == 1
      g = gc
      d = fmpz(p)
    else
      if degree(gc) < degree(g)
        g = gc
        d = fmpz(p)
      elseif degree(gc) > degree(g)
        continue
      else
        g, d = induce_crt(g, d, gc, fmpz(p), true)
      end
    end
    if g == last_g
      r = mod(a, g)
      if iszero(r)
        r = mod(b, g)
        if iszero(r)
          return g
        end
      end
    else
      last_g = g
    end
  end
end

#seems to be faster than gcdx - if problem large enough.
#rational reconstructio is expensive - enventually
#TODO: figure out the denominators in advance. Resultants?

function gcdx_modular(a::GenPoly{nf_elem}, b::GenPoly{nf_elem})
  a = a*(1//leading_coefficient(a))
  b = b*(1//leading_coefficient(b))
  global p_start
  p = p_start
  K = base_ring(parent(a))
  @assert parent(a) == parent(b)
  g = zero(a)
  d = fmpz(1)
  last_g = parent(a)(0)
  while true
    p = next_prime(p)
    me = modular_init(K, p)
    fp = deepcopy(Hecke.modular_proj(a, me))  # bad!!!
    gp = Hecke.modular_proj(b, me)
    ap = similar(gp)
    bp = similar(gp)
    for i=1:length(gp)
      gp[i], ap[i], bp[i] = gcdx(fp[i], gp[i])
    end
    gc = Hecke.modular_lift(gp, me)
    aa = Hecke.modular_lift(ap, me)
    bb = Hecke.modular_lift(bp, me)
    if d == 1
      g = gc
      ca = aa
      cb = bb
      d = fmpz(p)
    else
      if degree(gc) < degree(g)
        g = gc
        ca = aa
        cb = bb
        d = fmpz(p)
      elseif degree(gc) > degree(g)
        continue
      else
        g, dd = induce_crt(g, d, gc, fmpz(p))
        ca, dd = induce_crt(ca, d, aa, fmpz(p))
        cb, d = induce_crt(cb, d, bb, fmpz(p))
      end
    end
    fl, ccb = Hecke.induce_rational_reconstruction(cb, d)
    if fl
      fl, cca = Hecke.induce_rational_reconstruction(ca, d)
    end
    if fl
      fl, gg = Hecke.induce_rational_reconstruction(g, d)
    end
    if fl
      r = mod(a, g)
      if iszero(r)
        r = mod(b, g)
        if iszero(r) && ((cca*a + ccb*b) == gg)
          return gg, cca, ccb
        end
      end
    end
  end
end
  
###########################################################################
function nf_poly_to_xy(f::PolyElem{Nemo.nf_elem}, x::PolyElem, y::PolyElem)
  K = base_ring(f)
  Qy = parent(K.pol)

  res = zero(parent(y))
  for i=degree(f):-1:0
    res *= y
    res += evaluate(Qy(coeff(f, i)), x)
  end
  return res
end

doc"""
  norm(f::PolyElem{nf_elem}) -> fmpq_poly

> The norm of f, i.e. the product of all conjugates of f taken coefficientwise.
"""
function norm(f::PolyElem{nf_elem})
  Kx = parent(f)
  K = base_ring(f)
  Qy = parent(K.pol)
  y = gen(Qy)
  Qyx, x = PolynomialRing(Qy, "x")
 
  Qx = PolynomialRing(QQ, "x")[1]
  Qxy = PolynomialRing(Qx, "y")[1]

  T = evaluate(K.pol, gen(Qxy))
  h = nf_poly_to_xy(f, gen(Qxy), gen(Qx))
  return resultant(T, h)
end

doc"""
  factor(f::fmpz_poly, K::NumberField) -> Dict{PolyElem{nf_elem}, Int}
  factor(f::fmpq_poly, K::NumberField) -> Dict{PolyElem{nf_elem}, Int}

> The factorisation of f over K (using Trager's method).
"""
function factor(f::fmpq_poly, K::AnticNumberField)
  Ky, y = PolynomialRing(K)
  return factor(evaluate(f, y))
end

function factor(f::fmpz_poly, K::AnticNumberField)
  Ky, y = PolynomialRing(K)
  Qz, z = PolynomialRing(FlintQQ)
  return factor(evaluate(Qz(f), y))
end


doc"""
  factor(f::PolyElem{nf_elem}) -> Dict{PolyElem{nf_elem}, Int}

> The factorisation of f (using Trager's method). f has to be squarefree.
"""
function factor(f::PolyElem{nf_elem})
  Kx = parent(f)
  K = base_ring(f)

  f == 0 && error("poly is zero")

  k = 0
  g = f
  N = 0

  while true
    N = norm(g)

    if !is_constant(N) && is_squarefree(N)
      break
    end

    k = k + 1
 
    g = compose(f, gen(Kx) - k*gen(K))
  end
  
  fac = factor(N)

  res = Dict{PolyElem{nf_elem}, Int64}()

  for i in keys(fac.fac)
    t = zero(Kx)
    for j in 0:degree(i)
      t = t + K(coeff(i, j))*gen(Kx)^j
    end
    t = compose(t, gen(Kx) + k*gen(K))
    res[gcd(f, t)] = 1
  end

  r = Fac{typeof(f)}()
  r.fac = res
  r.unit = Kx(1)
  return r
end

################################################################################
#
# Operations for nf_elem
#
################################################################################

function gen!(r::nf_elem)
   a = parent(r)
   ccall((:nf_elem_gen, :libflint), Void, 
         (Ptr{nf_elem}, Ptr{AnticNumberField}), &r, &a)
   return r
end

function one!(r::nf_elem)
   a = parent(r)
   ccall((:nf_elem_one, :libflint), Void, 
         (Ptr{nf_elem}, Ptr{AnticNumberField}), &r, &a)
   return r
end

function one(r::nf_elem)
   a = parent(r)
   return one(a)
end

function zero(r::nf_elem)
   return zero(parent(r))
end

*(a::nf_elem, b::Integer) = a * fmpz(b)

doc"""
***
   norm_div(a::nf_elem, d::fmpz, nb::Int) -> fmpz

> Computes divexact(norm(a), d) provided the result has at most nb bits.
> Typically, a is in some ideal and d is the norm of the ideal.
"""
function norm_div(a::nf_elem, d::fmpz, nb::Int)
   z = fmpq()
   #CF the resultant code has trouble with denominators,
   #   this "solves" the problem, but it should probably be
   #   adressed in c
   de = den(a)
   n = degree(parent(a))
   ccall((:nf_elem_norm_div, :libflint), Void,
         (Ptr{fmpq}, Ptr{nf_elem}, Ptr{AnticNumberField}, Ptr{fmpz}, UInt),
         &z, &(a*de), &a.parent, &(d*de^n), UInt(nb))
   return z
end

function sub!(a::nf_elem, b::nf_elem, c::nf_elem)
   ccall((:nf_elem_sub, :libflint), Void,
         (Ptr{nf_elem}, Ptr{nf_elem}, Ptr{nf_elem}, Ptr{AnticNumberField}),
 
         &a, &b, &c, &a.parent)
end

function ^(x::nf_elem, y::fmpz)
  if y < 0
    return inv(x)^(-y)
  elseif y == 0
    return parent(x)(1)
  elseif y == 1
    return deepcopy(x)
  elseif mod(y, 2) == 0
    z = x^(div(y, 2))
    return z*z
  elseif mod(y, 2) == 1
    return x^(y-1) * x
  end
end

doc"""
***
    roots(f::GenPoly{nf_elem}) -> Array{nf_elem, 1}

> Computes all roots of a polynomial $f$. It is assumed that $f$ is is non-zero,
> squarefree and monic.
"""
function roots(f::GenPoly{nf_elem}, max_roots::Int = degree(f))
  O = maximal_order(base_ring(f))
  d = degree(f)
  deno = den(coeff(f, d), O)
  for i in (d-1):-1:0
    ai = coeff(f, i)
    if !iszero(ai)
      deno = lcm(deno, den(ai, O))
    end
  end

  g = deno*f

  Ox, x = PolynomialRing(O, "x")
  goverO = Ox([ O(coeff(g, i)) for i in 0:d])

  if !isone(lead(goverO))
    deg = degree(f)
    a = lead(goverO)
    b = one(O)
    for i in deg-1:-1:0
      setcoeff!(goverO, i, b*coeff(goverO, i))
      b = b*a
    end
    setcoeff!(goverO, deg, one(O))
    r = _roots_hensel(goverO, max_roots)
    return [ divexact(elem_in_nf(y), elem_in_nf(a)) for y in r ]
  end

  A = _roots_hensel(goverO)

  return [ elem_in_nf(y) for y in A ]
end


doc"""
***
    root(a::nf_elem, n::Int) -> Bool, nf_elem

> Determines whether $a$ has an $n$-th root. If this is the case,
> the root is returned.
"""
function root(a::nf_elem, n::Int)
  #println("Compute $(n)th root of $a")
  Kx, x = PolynomialRing(parent(a), "x")

  f = x^n - a

  fac = factor(f)
  #println("factorization is $fac")

  for i in keys(fac)
    if degree(i) == 1
      return (true, -coeff(i, 0)//coeff(i, 1))
    end
  end

  return (false, zero(parent(a)))
end

function num(a::nf_elem)
   const _one = fmpz(1)
   z = copy(a)
   ccall((:nf_elem_set_den, :libflint), Void,
         (Ptr{nf_elem}, Ptr{fmpz}, Ptr{AnticNumberField}),
         &z, &_one, &a.parent)
   return z
end

copy(d::nf_elem) = deepcopy(d)

################################################################################
#
#  Minkowski map
#
################################################################################

doc"""
***
    minkowski_map(a::nf_elem, abs_tol::Int) -> Array{arb, 1}

> Returns the image of $a$ under the Minkowski embedding.
> Every entry of the array returned is of type `arb` with radius less then
> `2^(-abs_tol)`.
"""
function minkowski_map(a::nf_elem, abs_tol::Int = 32)
  K = parent(a)
  A = Array(arb, degree(K))
  r, s = signature(K)
  c = conjugate_data_arb(K)
  R = PolynomialRing(AcbField(c.prec), "x")[1]
  f = R(parent(K.pol)(a))
  CC = AcbField(c.prec)
  T = PolynomialRing(CC, "x")[1]
  g = T(f)

  for i in 1:r
    t = evaluate(g, c.real_roots[i])
    @assert isreal(t)
    A[i] = real(t)
    if !radiuslttwopower(A[i], -abs_tol)
      refine(c)
      return minkowski_map(a, abs_tol)
    end
  end

  t = base_ring(g)()

  for i in 1:s
    t = evaluate(g, c.complex_roots[i])
    t = sqrt(CC(2))*t
    if !radiuslttwopower(t, -abs_tol)
      refine(c)
      return minkowski_map(a, abs_tol)
    end
    A[r + 2*i - 1] = real(t)
    A[r + 2*i] = imag(t)
  end

  return A
end

function t2{T}(x::nf_elem, abs_tol::Int = 32, ::Type{T} = arb)
  p = 2*abs_tol
  z = mapreduce(y -> y^2, +, minkowski_map(x, p))
  while !radiuslttwopower(z, -abs_tol)
    p = 2 * p
    z = mapreduce(y -> y^2, +, minkowski_map(x, p))
  end
  return z
end

################################################################################
#
#  Conjugates and real embeddings
#
################################################################################

doc"""
***
    conjugates_arb(x::nf_elem, abs_tol::Int) -> Array{acb, 1}

> Compute the the conjugates of `x` as elements of type `acb`.
> Recall that we order the complex conjugates
> $\sigma_{r+1}(x),...,\sigma_{r+2s}(x)$ such that
> $\sigma_{i}(x) = \overline{sigma_{i + s}(x)}$ for $r + 1 \leq i \leq r + s$.
>
> Every entry `y` of the array returned satisfies
> `radius(real(y)) < 2^abs_tol` and `radius(imag(y)) < 2^abs_tol` respectively.
"""
function conjugates_arb(x::nf_elem, abs_tol::Int = 32)
  K = parent(x)
  d = degree(K)
  c = conjugate_data_arb(K)
  r, s = signature(K)
  conjugates = Array(acb, r + 2*s)
  CC = AcbField(c.prec)

  for i in 1:r
    conjugates[i] = CC(evaluate(parent(K.pol)(x), c.real_roots[i]))
    if !isfinite(conjugates[i]) || (abs_tol != -1 && !radiuslttwopower(conjugates[i], -abs_tol))
      refine(c)
      return conjugates_arb(x, abs_tol)
    end
  end

  for i in 1:s
    conjugates[r + i] = evaluate(parent(K.pol)(x), c.complex_roots[i])
    if !isfinite(conjugates[i]) || (abs_tol != -1 && !radiuslttwopower(conjugates[i], -abs_tol))
      refine(c)
      return conjugates_arb(x, abs_tol)
    end
    conjugates[r + i + s] = Nemo.conj(conjugates[r + i])
  end
 
  return conjugates
end

doc"""
***
    conjugates_arb_real(x::nf_elem, abs_tol::Int) -> Array{arb, 1}

> Compute the the real conjugates of `x` as elements of type `arb`.
>
> Every entry `y` of the array returned satisfies
> `radius(y) < 2^abs_tol`.
"""
function conjugates_arb_real(x::nf_elem, abs_tol::Int = 32)
  r1, r2 = signature(parent(x))
  c = conjugates_arb(x, abs_tol)
  z = Array(arb, r1)

  for i in 1:r
    z[i] = real(c[i])
  end

  return z
end

doc"""
***
    conjugates_arb_complex(x::nf_elem, abs_tol::Int) -> Array{acb, 1}

> Compute the the complex conjugates of `x` as elements of type `acb`.
> Recall that we order the complex conjugates
> $\sigma_{r+1}(x),...,\sigma_{r+2s}(x)$ such that
> $\sigma_{i}(x) = \overline{sigma_{i + s}(x)}$ for $r + 1 \leq i \leq r + s$.
>
> Every entry `y` of the array returned satisfies
> `radius(real(y)) < 2^abs_tol` and `radius(imag(y)) < 2^abs_tol`.
"""
function conjugates_arb_complex(x::nf_elem, abs_tol::Int)
end

doc"""
***
    conjugates_arb_log(x::nf_elem, abs_tol::Int) -> Array{arb, 1}

> Returns the elements
> $(\log(\lvert \sigma_1(x) \rvert),\dotsc,\log(\lvert\sigma_r(x) \rvert),
> \dotsc,2\log(\lvert \sigma_{r+1}(x) \rvert),\dotsc,
> 2\log(\lvert \sigma_{r+s}(x)\rvert))$ as elements of type `arb` radius
> less then `2^abs_tol`.
"""
function conjugates_arb_log(x::nf_elem, abs_tol::Int)
  K = parent(x)
  d = degree(K)
  r1, r2 = signature(K)
  c = conjugate_data_arb(K)

  # We should replace this using multipoint evaluation of libarb
  z = Array(arb, r1 + r2)
  xpoly = arb_poly(parent(K.pol)(x), c.prec)
  for i in 1:r1
    #z[i] = log(abs(evaluate(parent(K.pol)(x), c.real_roots[i])))
    o = ArbField(c.prec)()
    ccall((:arb_poly_evaluate, :libarb), Void, (Ptr{arb}, Ptr{arb_poly}, Ptr{arb}, Int), &o, &xpoly, &c.real_roots[i], c.prec)
    abs!(o, o)
    log!(o, o)
    z[i] = o

    #z[i] = log(abs(evaluate(parent(K.pol)(x),c.real_roots[i])))
    if !isfinite(z[i]) || !radiuslttwopower(z[i], -abs_tol)
      refine(c)
      return conjugates_arb_log(x, abs_tol)
    end
  end

  tacb = AcbField(c.prec)()
  for i in 1:r2
    oo = ArbField(c.prec)()
    ccall((:arb_poly_evaluate_acb, :libarb), Void, (Ptr{acb}, Ptr{arb_poly}, Ptr{acb}, Int), &tacb, &xpoly, &c.complex_roots[i], c.prec)
    abs!(oo, tacb)
    log!(oo, oo)
    mul2exp!(oo, oo, 1)
    z[r1 + i] = oo

    #z[r1 + i] = 2*log(abs(evaluate(parent(K.pol)(x), c.complex_roots[i])))
    if !isfinite(z[r1 + i]) || !radiuslttwopower(z[r1 + i], -abs_tol)
      refine(c)
      return conjugates_arb_log(x, abs_tol)
    end
  end
  return z
end

function conjugates_arb_log(x::nf_elem, R::ArbField)
  z = conjugates_arb_log(x, R.prec)
  return map(R, z)
end

################################################################################
#
#  Torsion units and related functions
#
################################################################################

doc"""
***
    is_torsion_unit(x::nf_elem, checkisunit::Bool = false) -> Bool
    
> Returns whether $x$ is a torsion unit, that is, whether there exists $n$ such
> that $x^n = 1$.
> 
> If `checkisunit` is `true`, it is first checked whether $x$ is a unit of the
> maximal order of the number field $x$ is lying in.
"""
function is_torsion_unit(x::nf_elem, checkisunit::Bool = false)
  if checkisunit
    _is_unit(x) ? nothing : return false
  end

  K = parent(x)
  d = degree(K)
  c = conjugate_data_arb(K)
  r, s = signature(K)

  while true
    @vprint :UnitGroup 2 "Precision is now $(c.prec) \n"
    l = 0
    @vprint :UnitGroup 2 "Computing conjugates ... \n"
    cx = conjugates_arb(x, c.prec)
    A = ArbField(c.prec)
    for i in 1:r
      k = abs(cx[i])
      if k > A(1)
        return false
      elseif isnonnegative(A(1) + A(1)//A(6) * log(A(d))//A(d^2) - k)
        l = l + 1
      end
    end
    for i in 1:s
      k = abs(cx[r + i])
      if k > A(1)
        return false
      elseif isnonnegative(A(1) + A(1)//A(6) * log(A(d))//A(d^2) - k)
        l = l + 1
      end
    end

    if l == r + s
      return true
    end
    refine(c)
  end
end

doc"""
***
    torsion_unit_order(x::nf_elem, n::Int)

> Given a torsion unit $x$ together with a multiple $n$ of its order, compute
> the order of $x$, that is, the smallest $k \in \mathbb Z_{\geq 1}$ such
> that $x^`k` = 1$.
>
> It is not checked whether $x$ is a torsion unit.
"""
function torsion_unit_order(x::nf_elem, n::Int)
  # This is lazy
  # Someone please change this
  y = deepcopy(x)
  for i in 1:n
    if y == 1
      return i
    end
    mul!(y, y, x)
  end
  error("Something odd in the torsion unit order computation")
end

################################################################################
#
#  Serialization
#
################################################################################

# This function can be improved by directly accessing the numerator
# of the fmpq_poly representing the nf_elem
doc"""
***
    write(io::IO, A::Array{nf_elem, 1}) -> Void

> Writes the elements of `A` to `io`. The first line are the coefficients of
> the defining polynomial of the ambient number field. The following lines
> contain the coefficients of the elements of `A` with respect to the power
> basis of the ambient number field.
"""
function write(io::IO, A::Array{nf_elem, 1})
  if length(A) == 0
    return
  else
    # print some useful(?) information
    print(io, "# File created by Hecke $VERSION_NUMBER, $(Base.Dates.now()), by function 'write'\n")
    K = parent(A[1])
    polring = parent(K.pol)

    # print the defining polynomial
    g = K.pol
    d = den(g)

    for j in 0:degree(g)
      print(io, coeff(g, j)*d)
      print(io, " ")
    end
    print(io, d)
    print(io, "\n")

    # print the elements
    for i in 1:length(A)

      f = polring(A[i])
      d = den(f)

      for j in 0:degree(K)-1
        print(io, coeff(f, j)*d)
        print(io, " ")
      end

      print(io, d)

      print(io, "\n")
    end
  end
end  

doc"""
***
    write(file::String, A::Array{nf_elem, 1}, flag::ASCIString = "w") -> Void

> Writes the elements of `A` to the file `file`. The first line are the coefficients of
> the defining polynomial of the ambient number field. The following lines
> contain the coefficients of the elements of `A` with respect to the power
> basis of the ambient number field.
>
> Unless otherwise specified by the parameter `flag`, the content of `file` will be
> overwritten.
"""
function write(file::String, A::Array{nf_elem, 1}, flag::String = "w")
  f = open(file, flag)
  write(f, A)
  close(f)
end

# This function has a bad memory footprint
doc"""
***
    read(io::IO, K::AnticNumberField, ::Type{nf_elem}) -> Array{nf_elem, 1}

> Given a file with content adhering the format of the `write` procedure,
> this functions returns the corresponding object of type `Array{nf_elem, 1}` such that
> all elements have parent $K$.

**Example**

    julia> Qx, x = QQ["x"]
    julia> K, a = NumberField(x^3 + 2, "a")
    julia> write("interesting_elements", [1, a, a^2])
    julia> A = read("interesting_elements", K, Hecke.nf_elem)
"""
function read(io::IO, K::AnticNumberField, ::Type{Hecke.nf_elem})
  Qx = parent(K.pol)

  A = Array{nf_elem, 1}()

  i = 1

  for ln in eachline(io)
    if ln[1] == '#'
      continue
    elseif i == 1
      # the first line read should contain the number field and will be ignored
      i = i + 1
    else
      coe = map(Hecke.fmpz, split(ln, " "))
      t = fmpz_poly(Array(slice(coe, 1:(length(coe) - 1))))
      t = Qx(t)
      t = divexact(t, coe[end])
      push!(A, K(t))
      i = i + 1
    end
  end
  
  return A
end

doc"""
***
    read(file::String, K::AnticNumberField, ::Type{nf_elem}) -> Array{nf_elem, 1}

> Given a file with content adhering the format of the `write` procedure,
> this functions returns the corresponding object of type `Array{nf_elem, 1}` such that
> all elements have parent $K$.

**Example**

    julia> Qx, x = QQ["x"]
    julia> K, a = NumberField(x^3 + 2, "a")
    julia> write("interesting_elements", [1, a, a^2])
    julia> A = read("interesting_elements", K, Hecke.nf_elem)
"""
function read(file::String, K::AnticNumberField, ::Type{Hecke.nf_elem})
  f = open(file, "r")
  A = read(f, K, Hecke.nf_elem)
  close(f)
  return A
end


function dot(a::Array{nf_elem, 1}, b::Array{fmpz, 1})
  d = zero(parent(a[1]))
  t = zero(d)
  for i=1:length(a)
    Nemo.mul!(t, a[i], b[i])
    Nemo.add!(d, d, t)
  end
  return d
end

type nf_elem_deg_1_raw
  num::Int  ## fmpz!
  den::Int
end

type nf_elem_deg_2_raw
  nu0::Int  ## fmpz - actually an fmpz[3]
  nu1::Int
  nu2::Int
  den::Int
end

type nf_elem_deg_n_raw  #actually an fmpq_poly_raw
  A::Ptr{Int} # fmpz
  den::Int # fmpz
  alloc::Int
  len::Int
end

type nmod_t
  n::Int
  ni::Int
  norm::Int
end

#nf_elem is a union of the three types above
#ignores the denominator completely

function nf_elem_to_nmod_poly_no_den!(r::nmod_poly, a::nf_elem)
  d = degree(a.parent)
  zero!(r)
  p = r.mod_n
  if d == 1
    ra = pointer_from_objref(a)
    s = ccall((:fmpz_fdiv_ui, :libflint), UInt, (Ptr{Void}, UInt), ra, p)
    ccall((:nmod_poly_set_coeff_ui, :libflint), Void, (Ptr{nmod_poly}, Int, UInt), &r, 0, s)
  elseif d == 2  
    ra = pointer_from_objref(a)
    s = ccall((:fmpz_fdiv_ui, :libflint), UInt, (Ptr{Void}, UInt), ra, p)
    ccall((:nmod_poly_set_coeff_ui, :libflint), Void, (Ptr{nmod_poly}, Int, UInt), &r, 0, s)
    s = ccall((:fmpz_fdiv_ui, :libflint), UInt, (Ptr{Void}, UInt), ra + sizeof(Int), p)
    ccall((:nmod_poly_set_coeff_ui, :libflint), Void, (Ptr{nmod_poly}, Int, UInt), &r, 1, s)
  else
    ccall((:_fmpz_vec_get_nmod_poly, :libhecke), Void, (Ptr{nmod_poly}, Ptr{Int}, Int), &r, a.elem_coeffs, a.elem_length)
# this works without libhecke:    
#    ccall((:nmod_poly_fit_length, :libflint), Void, (Ptr{nmod_poly}, Int), &r, a.elem_length)
#    ccall((:_fmpz_vec_get_nmod_vec, :libflint), Void, (Ptr{Void}, Ptr{Void}, Int, nmod_t), r._coeffs, a.elem_coeffs, a.elem_length, nmod_t(p, 0, 0))
#    r._length = a.elem_length
#    ccall((:_nmod_poly_normalise, :libflint), Void, (Ptr{nmod_poly}, ), &r)
  end
end

function nf_elem_to_nmod_poly_den!(r::nmod_poly, a::nf_elem)
  d = degree(a.parent)
  p = r.mod_n
  if d == 1
    ra = pointer_from_objref(a)
    den = ccall((:fmpz_fdiv_ui, :libflint), UInt, (Ptr{Void}, UInt), ra + sizeof(Int), p)
  elseif d == 2  
    ra = pointer_from_objref(a)
    den = ccall((:fmpz_fdiv_ui, :libflint), UInt, (Ptr{Void}, UInt), ra + 3*sizeof(Int), p)
  else  
    den = ccall((:fmpz_fdiv_ui, :libflint), UInt, (Ptr{Int}, UInt), &a.elem_den, p)
  end
  den = ccall((:n_invmod, :libflint), UInt, (UInt, UInt), den, p)
  nf_elem_to_nmod_poly_no_den!(r, a)
  mul!(r, r, den)
end

function nf_elem_to_nmod_poly(Rx::Nemo.NmodPolyRing, a::nf_elem)
  r = Rx()
  nf_elem_to_nmod_poly_den!(r, a)
  return r
end


(R::Nemo.NmodPolyRing)(a::nf_elem) = nf_elem_to_nmod_poly(R, a)

# Characteristic

characteristic(::AnticNumberField) = 0

#

show_minus_one(::Type{nf_elem}) = false

