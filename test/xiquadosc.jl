#!/usr/bin/env julia

using Hwloc
addprocs(Hwloc.num_physical_cores())
println("hostname: ", gethostname())
println("julia version: ", VERSION)
println("nprocs: ", nprocs())
println("nworkers: ", nworkers())


@everywhere dir = "/home/hsgg/research/hgebhardt/code/mypy"
try
	@everywhere include("$dir/pkspec.jl")  # make sure to use same spline!
	@everywhere include("$dir/bisect.jl")
	@everywhere include("$dir/quadosc.jl")
	@everywhere include("$dir/sphbes/sphbes.jl")
catch
	println("Cannot load essential libraries from `$dir`")
	println("They are not included because the license is unclear to me.")
	println("What is the numerical recipes license?")
	error("Cannot load essential libraries.")
end

@everywhere using PkSpectrum
@everywhere using QuadOsc
@everywhere using SphBes
@everywhere using QuadGK: quadgk



@everywhere function integrand(lnk, r, pwr, ell=0, nu=0)
    if lnk > 700
        return 0.0
    end
    k = exp(lnk)
    if k > 1e50
        return 0.0
    end
    res = sphbesj(k*r, ell) * k^(3-nu) * pwr(k)
    #println("lnk=$lnk\tk=$k\tnu=$nu\tres=$res")
    if !isfinite(res)
        error("not finite!")
    end
    return res
end


@everywhere function corrfunc(r::Number, pwr, ell=0, nu=0; reltol=1e-10, order=127)
	if r == 0
		return 0.0
	end
	integ(lnk) = integrand(lnk, r, pwr, ell, nu)
	pivot = 0.0
	#print("computing r=$r... ")
	I0, E0 = quadgk(integ, -Inf, pivot, reltol=reltol, order=order)
	I1, E1 = quadosc(integ, pivot, Inf, n -> log(n * pi / r), beta=1.0,
		reltol=reltol, order=order)
	factor = 1 / (2 * pi^2 * r^nu)
	return factor * (I0 + I1), factor * (E0 + E1)
end

function corrfunc(rr, pwr, ell=0, nu=0; reltol=1e-10, order=127)
	print("ξ(r), ℓ=$ell, ν=$nu: ")
	if (nu == -2 && ell ∈ [0, 1, 2, 3, 4] ||
	    nu == -1 && ell ∈ [1])
		println("Skipping...")
		return fill(NaN, length(rr)), fill(NaN, length(rr))
	end
	@time tmp = pmap(r -> corrfunc(r, pwr, ell, nu, reltol=reltol, order=order), rr)
	xi = Array{Float64}(length(rr))
	xie = Array{Float64}(length(rr))
	for i=1:length(rr)
		xi[i] = tmp[i][1]
		xie[i] = tmp[i][2]
	end
	return xi, xie
end


function more_xi(ℓ=0)
	fname = "data/planck_base_plikHM_TTTEEE_lowTEB_lensing_post_BAO_H070p6_JLA_matterpower.dat"
	pkin = PkFile(fname)#; ns=0.9672)
	r = linspace(1.0, 200.0, Int(199/0.1) + 1)

	xiℓ = [corrfunc(r, pkin, ℓ, ν)[1] for ν=-2:3]

	writedlm("data/xiquadosc_plus_ell$ℓ.tsv", [r xiℓ...])
end


more_xi(0)
more_xi(1)
more_xi(2)
more_xi(3)
more_xi(4)
