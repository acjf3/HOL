 (*------------------------------------------------------------------
  * CACHE
  *
  * Cache an operation which depends on a set of theorems as
  * part of its input - e.g. "contextual" decision procedures
  * such as CTXT_ARITH
  *
  * Two arguments are needed.  The first should determine if a given
  * term is relevant to the decision procedure i.e., might be rewritten
  * by it.  The second should be a conversion i.e. convert a term t to
  * |- t = x for some value x.
  *
  * Returns a new conversion, and a reference to a table used
  * as a cache.  The table is returned to enable users to
  * analyse its contents (functions will be provided for this at a later
  * date)
  *-----------------------------------------------------------------*)

signature Cache =
sig
  include Abbrev

  type cache
  val CACHE :(term -> bool) * (thm list->conv) -> (thm list -> conv) * cache
  val clear_cache : cache -> unit;
  val print_cache : cache -> unit
end
