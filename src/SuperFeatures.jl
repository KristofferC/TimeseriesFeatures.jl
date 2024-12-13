module SuperFeatures

import ..Features: AbstractFeature, Feature, getmethod, getname, getkeywords,
                   getdescription, fullmethod
import ..FeatureSets: AbstractFeatureSet, FeatureSet, getmethods, getnames, getdescriptions,
                      getkeywords
import ..FeatureArrays: FeatureVector, AbstractDimArray, _construct, _setconstruct,
                        FeatureArray, _featuredim, LabelledFeatureArray
using ..DimensionalData
import Base: union, intersect, setdiff, convert, promote_rule, promote_eltype, cat, +, \
using ProgressLogging

export SuperFeature,
       SuperFeatureSet,
       Super, AbstractSuper,
       getsuper, getfeature

abstract type AbstractSuperFeature <: AbstractFeature end

## Univariate features
Base.@kwdef struct SuperFeature{F, G} <:
                   AbstractSuperFeature where {F <: Function, G <: AbstractFeature}
    method::F
    name::Symbol = Symbol(method)
    description::String = ""
    keywords::Vector{String} = [""]
    super::G
end
const Identity = Feature(identity, :identity, "Identity function", ["transformation"])
function SuperFeature(method::F, name = Symbol(method),
                      keywords::Vector{String} = [""], description::String = "";
                      super::G) where {F <: Function, G <: AbstractFeature}
    SuperFeature(; super, method, name, keywords, description)
end
function SuperFeature(method::F, name, description::String,
                      keywords::Vector{String} = [""];
                      super) where {F <: Function}
    SuperFeature(; super, method, name, keywords, description)
end
function SuperFeature(f::Feature{F}, super::Feature{G}) where {F <: Function, G <: Function}
    SuperFeature{F, Feature{G}}(f.method, f.name, f.description, f.keywords, super)
end
Base.convert(::Type{SuperFeature}, x::Feature{F}) where {F <: Function} = SuperFeature(x)
SuperFeature(f::Feature{F}) where {F <: Function} = SuperFeature(f, Identity)
SuperFeature(f::SuperFeature) = f

# * Helper functions
getsuper(𝒇::AbstractSuperFeature) = 𝒇.super
getsuper(::Feature) = ()
getfeature(𝑓::AbstractSuperFeature) = Feature(getmethod(𝑓))
fullmethod(𝑓::AbstractSuperFeature) = getmethod(𝑓) ∘ getsuper(𝑓)

# (𝑓::SuperFeature)(x::AbstractVector{<:Number}) = x |> fullmethod(𝑓)
# (𝑓::SuperFeature)(x::DimensionalData.AbstractDimVector) = x |> getsuper(𝑓) |> getmethod(𝑓)
# function (𝑓::SuperFeature)(X::DimensionalData.AbstractDimArray)
#     FeatureArray(getmethod(𝑓).(getsuper(𝑓)(X)),
#                  (_featuredim([getname(𝑓)]), dims(X)[2:end]...); refdims = refdims(X),
#                  name = name(X), metadata = metadata(X))
# end
# function (𝑓::SuperFeature)(X::DimensionalData.AbstractDimMatrix)
#     FeatureArray(getmethod(𝑓).(getsuper(𝑓)(X)).data,
#                  (_featuredim([getname(𝑓)]), dims(X)[2:end]...); refdims = refdims(X),
#                  name = name(X), metadata = metadata(X))
# end

const SuperFeatureSet = FeatureSet{<:AbstractSuperFeature}

# SuperPairwiseFeatureSet = SuperFeatureSet
SuperFeatureSet(𝒇::AbstractVector{<:AbstractSuperFeature}) = FeatureSet(𝒇)
SuperFeatureSet(𝒇::FeatureSet) = SuperFeatureSet(SuperFeature.(𝒇))
function SuperFeatureSet(methods::AbstractVector{<:Function}, names::Vector{Symbol},
                         descriptions::Vector{String}, keywords, super)
    SuperFeature.(methods, names, descriptions, keywords, super) |> FeatureSet
end
function SuperFeatureSet(methods::Function, args...)
    [SuperFeature(methods, args...)] |> FeatureSet
end
function SuperFeatureSet(; methods, names, keywords, descriptions, super)
    SuperFeatureSet(methods, names, keywords, descriptions, super)
end
SuperFeatureSet(f::AbstractFeature) = SuperFeatureSet([f])

# SuperFeatureSet(𝒇::Vector{Feature}) = SuperFeatureSet(getmethods(𝒇), getnames(𝒇), getdescriptions(𝒇), getkeywords(𝒇), getsuper(first(𝒇)))
getindex(𝒇::AbstractFeatureSet, I) = SuperFeatureSet(getfeatures(𝒇)[I])
# SuperFeatureSet(𝒇::Vector{Feature}) = FeatureSet(𝒇) # Just a regular feature set

function superloop(f::AbstractSuperFeature, supervals, x)
    getmethod(f)(supervals[getname(getsuper(f))])
end

function (𝒇::SuperFeatureSet)(x::AbstractVector{<:T},
                              return_type::Type = Float64) where {T <: Number}
    F = LabelledFeatureArray(Vector{return_type}(undef, length(𝒇)), 𝒇; x)
    supers = getsuper.(𝒇)
    ℱ = supers |> unique |> FeatureSet
    supervals = [f(x) for f in ℱ]
    idxs = indexin(supers, ℱ)
    F .= [convert(return_type, getmethod(f)(supervals[i])) for (i, f) in zip(idxs, 𝒇)]
    return F
end

# function (𝒇::SuperFeatureSet)(x::AbstractVector{<:Number}; kwargs...)::FeatureVector
#     ℱ = getsuper.(𝒇) |> unique |> FeatureSet
#     supervals = Dict(getname(f) => f(x) for f in ℱ)
#     FeatureArray(reduce(vcat, [superloop(𝑓, supervals, x) for 𝑓 in 𝒇]), 𝒇; kwargs...)
# end
# # function (𝒇::SuperFeatureSet)(X::AbstractArray; kwargs...)
# #     ℱ = getsuper.(𝒇) |> unique |> FeatureSet
# #     supervals = Array{Any}(undef, (length(ℱ), size(X)[2:end]...)) # Can we be more specific with the types?
# #     threadlog = 0
# #     threadmax = 2.0 .* prod(size(X)[2:end])
# #     l = size(X, 1) > 1000 ? Threads.ReentrantLock() : nothing
# #     @withprogress name="TimeseriesFeatures" begin
# #         idxs = CartesianIndices(size(X)[2:end])
# #         Threads.@threads for i in idxs
# #             supervals[:, i] = vec([f(X[:, i]) for f in ℱ])
# #             if !isnothing(l)
# #                 lock(l)
# #                 try
# #                     threadlog += 1
# #                     @logprogress threadlog / threadmax
# #                 finally
# #                     unlock(l)
# #                 end
# #             end
# #         end
# #         supervals = FeatureArray(supervals, ℱ)
# #         f1 = superloop.(𝒇, [supervals[:, first(idxs)]], [X[:, first(idxs)]]) # Assume same output type for all time series
# #         F = similar(f1, (length(𝒇), size(X)[2:end]...))
# #         F[:, first(idxs)] .= f1
# #         Threads.@threads for i in idxs[2:end]
# #             F[:, i] .= superloop.(𝒇, [supervals[:, i]], [X[:, i]])
# #             if !isnothing(l)
# #                 lock(l)
# #                 try
# #                     threadlog += 1
# #                     @logprogress threadlog / threadmax
# #                 finally
# #                     unlock(l)
# #                 end
# #             end
# #         end
# #         return FeatureArray(F, 𝒇; kwargs...)
# #     end
# # end
# function (𝒇::SuperFeatureSet)(X::AbstractVector{<:AbstractVector}; kwargs...)
#     ℱ = getsuper.(𝒇) |> unique |> FeatureSet
#     supervals = Array{Any}(undef, (length(ℱ), length(X))) # Can we be more specific with the types?
#     threadlog = 0
#     threadmax = 2.0 .* prod(size(X)[2:end])
#     l = size(X, 1) > 1000 ? Threads.ReentrantLock() : nothing
#     @withprogress name="TimeseriesFeatures" begin
#         idxs = eachindex(X)
#         Threads.@threads for i in idxs
#             supervals[:, i] = vec([f(X[i]) for f in ℱ])
#             if !isnothing(l)
#                 lock(l)
#                 try
#                     threadlog += 1
#                     @logprogress threadlog / threadmax
#                 finally
#                     unlock(l)
#                 end
#             end
#         end
#         supervals = FeatureArray(supervals, ℱ)
#         f1 = superloop.(𝒇, [supervals[:, first(idxs)]], [X[first(idxs)]]) # Assume same output type for all time series
#         F = similar(f1, (length(𝒇), length(X)))
#         F[:, first(idxs)] .= f1
#         Threads.@threads for i in idxs[2:end]
#             F[:, i] .= superloop.(𝒇, [supervals[:, i]], [X[i]])
#             if !isnothing(l)
#                 lock(l)
#                 try
#                     threadlog += 1
#                     @logprogress threadlog / threadmax
#                 finally
#                     unlock(l)
#                 end
#             end
#         end
#         return FeatureArray(F, 𝒇; kwargs...)
#     end
# end
# function (𝒇::SuperFeatureSet)(x::AbstractDimArray; kwargs...)
#     F = 𝒇(parent(x))
#     FeatureArray(parent(F),
#                  (_featuredim(getnames(𝒇)), dims(x)[2:end]...); refdims = refdims(x),
#                  name = name(x), metadata = metadata(x), kwargs...)
# end

# (𝒇::SuperFeatureSet)(X::AbstractDimArray) = _setconstruct(𝒇, X)

## Pairwise features
abstract type AbstractSuper{F, S} <: AbstractSuperFeature where {F, S} end
struct Super{F, S} <: AbstractSuper{F, S}
    feature::F
    super::S
    name::Symbol
end
Super(feature, super) = Super(feature, super, Symbol(feature.name, "_", super.name))
getmethod(𝑓::AbstractSuper) = 𝑓.feature.method
getname(𝑓::AbstractSuper) = 𝑓.name
getnames(𝑓::AbstractSuper) = [𝑓.name]
getkeywords(𝑓::AbstractSuper) = unique([𝑓.feature.keywords..., 𝑓.super.keywords...])
getdescription(𝑓::AbstractSuper) = 𝑓.feature.description * " [of] " * 𝑓.super.description
getsuper(𝑓::AbstractSuper) = 𝑓.super
getfeature(𝑓::AbstractSuper) = 𝑓.feature

function (𝑓::AbstractSuper{F, S})(x::AbstractVector{<:Number}) where {F <: AbstractFeature,
                                                                      S <: AbstractFeature}
    getfeature(𝑓)(getsuper(𝑓)(x))
end
function (𝑓::AbstractSuper{F, S})(x::AbstractArray{<:Number}) where {F <: AbstractFeature,
                                                                     S <: AbstractFeature}
    getfeature(𝑓)(getsuper(𝑓)(x))
end
function (𝑓::AbstractSuper{F, S})(x::AbstractDimArray) where {F <: AbstractFeature,
                                                              S <: AbstractFeature}
    getfeature(𝑓)(getsuper(𝑓)(x))
end
function (𝑓::AbstractSuper{F, S})(x::DimensionalData.AbstractDimMatrix) where {
                                                                               F <:
                                                                               AbstractFeature,
                                                                               S <:
                                                                               AbstractFeature
                                                                               }
    getfeature(𝑓)(getsuper(𝑓)(x))
end
function (𝑓::AbstractSuper{F, S})(x::AbstractArray{<:AbstractArray}) where {
                                                                            F <:
                                                                            AbstractFeature,
                                                                            S <:
                                                                            AbstractFeature}
    map(getfeature(𝑓) ∘ getsuper(𝑓), x)
end

# * Feature set arithmetic
function promote_rule(::Type{<:SuperFeatureSet}, ::Type{<:FeatureSet})
    SuperFeatureSet{SuperFeature}
end
# function promote_rule(::Type{<:AbstractSuperFeature}, ::Type{<:AbstractFeature})
#     SuperFeature
# end
# function promote_rule(::Type{<:AbstractFeature}, ::Type{<:AbstractSuperFeature})
#     SuperFeature
# end
function promote_rule(::Type{SuperFeature{F, G}}, ::Type{<:AbstractFeature}) where {F, G}
    SuperFeature
end
function promote_rule(::Type{AbstractSuperFeature}, ::Type{<:AbstractFeature})
    SuperFeature
end
function promote_rule(::Type{AbstractSuperFeature}, ::Type{<:Feature{<:H}}) where {H}
    SuperFeature
end
function promote_rule(::Type{SuperFeature}, ::Type{<:Feature{<:H}}) where {H}
    SuperFeature
end
function Base.promote_eltype(v1::AbstractFeatureSet, v2::AbstractFeatureSet)
    Base.promote_type(eltype(v1), eltype(v2))
end

# ! None of these are type stable
function Base.vcat(V1::A, V2::B) where {A <: AbstractFeatureSet, B <: AbstractFeatureSet}
    T = Base.promote_eltype(V1, V2)
    FeatureSet(Base.typed_vcat(T, T.(V1), T.(V2)))
end
(+)(𝒇::AbstractFeatureSet, 𝒇′::AbstractFeatureSet) = vcat(𝒇, 𝒇′)
(+)(𝒇::AbstractFeature, 𝒇′::AbstractFeature) = FeatureSet([𝒇, 𝒇′])
function intersect(𝒇::A, 𝒇′::B) where {A <: AbstractFeatureSet, B <: AbstractFeatureSet}
    T = promote_eltype(𝒇, 𝒇′)
    FeatureSet(intersect(T.(𝒇), T.(𝒇′)))
end
function union(𝒇::A, 𝒇′::B) where {A <: AbstractFeatureSet, B <: AbstractFeatureSet}
    T = promote_eltype(𝒇, 𝒇′)
    FeatureSet(union(T.(𝒇), T.(𝒇′)))
end
function setdiff(𝒇::A, 𝒇′::B) where {A <: AbstractFeatureSet, B <: AbstractFeatureSet}
    T = promote_eltype(𝒇, 𝒇′)
    FeatureSet(setdiff(T.(𝒇), T.(𝒇′)))
end
(\)(𝒇::AbstractFeatureSet, 𝒇′::AbstractFeatureSet) = setdiff(𝒇, 𝒇′)

# Allow operations between FeatureSet and Feature by converting the Feature
for p in [:+, :\, :setdiff, :union, :intersect]
    eval(quote
             ($p)(𝒇::AbstractFeatureSet, f::AbstractFeature) = ($p)(𝒇, FeatureSet(f))
             ($p)(f::AbstractFeature, 𝒇::AbstractFeatureSet) = ($p)(FeatureSet(f), 𝒇)
         end)
end

end # module
