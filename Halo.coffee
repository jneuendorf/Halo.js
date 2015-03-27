####################################################################################
# GENERAL HELPER FUNCTIONS
__NULL__ = {}
slice = Array::slice
toArray = (args) ->
    return slice.call args

each = (arr, callback) ->
    for elem, idx in arr
        if callback(elem, idx) is false
            return arr
    return arr

####################################################################################
# RING HELPER FUNCTIONS
execSuper = (clss, name, dest, args) ->
    if not (f = dest[name])?
        return __NULL__
    # add required MRO related data to function that's not in a Halo class but is visited during the MRO lookup
    # this enables you to include non-Halo classes in the MRO
    if not f.__class__ or not f.__name__
        f.__class__ = clss
        f.__name__  = name

    if typeof f is "function"
        return f.apply(@, args)
    return f

_super = (clss, name, args...) ->
    MRO = @constructor.__mro__
    # go through MRO and find 1st class with according variable (= name)
    for c in MRO.slice(MRO.indexOf(clss) + 1)
        if (res = execSuper.call(@, c, name, c.prototype, args)) isnt __NULL__
            return res
        # super constructor => name cannot match
        if name is Halo.config.constructorName
            return c.apply(@, args)

    console.warn "There is no 'this._super()' for the following function:", name, "of", (if clss.__name__ isnt Halo.config.constructorName then clss.__name__ else clss.name), "(in MRO of #{@constructor.name})"
    return args[0] or null

_superStatic = (clss, name, args...) ->
    # go through MRO and find 1st class with according variable (= name)
    MRO = @__mro__
    for c in MRO.slice(MRO.indexOf(clss) + 1)
        if (res = execSuper.call(@, c, name, c, args)) isnt __NULL__
            return res

    console.warn "There is no 'this._super()' for the following function:", name, "of", clss.__name__, "(in MRO of #{@name})"
    return args[0] or null

classFromObject = (name, obj) ->
    if obj.hasOwnProperty "constructor"
        ctorStr = obj.constructor.toString().replace("function ", "function #{name}").replace(/\n/g, "")
    else
        ctorStr = "function #{name}(){ this._super.apply(this, arguments) }"

    clss = eval("(#{ctorStr})")
    clss.__class__  = clss
    clss.__name__   = Halo.config.constructorName
    clss.__mro__ = []

    # prototype vars
    for key, val of obj when key not in ["constructor"].concat(Halo.config.staticKeys)
        val.__name__ = key
        val.__class__ = clss
        clss::[key] = val

    # static vars
    for key in Halo.config.staticKeys
        if (o = obj[key])?
            for key, val of o
                val.__name__ = key
                val.__class__ = clss
                clss[key] = val

    # non-static
    clss.prototype._super = () ->
        caller = arguments.callee.caller
        return _super.apply(@, [caller.__class__, caller.__name__].concat(toArray arguments))

    # static
    clss._super = () ->
        caller = arguments.callee.caller
        return _superStatic.apply(@, [caller.__class__, caller.__name__].concat(toArray arguments))

    return clss

# C3 merge() implementation (taken from https://github.com/nicolas-van/ring.js)
mergeMRO = (toMerge) ->
    __mro__ = []
    current = toMerge.slice(0)

    loop
        found = false
        i = -1
        while ++i < current.length
            cur = current[i]

            if cur.length is 0
                continue

            currentClass = cur[0]

            # get 1st element where currentClass is in the tail of the element
            isInTail = false
            for lst in current when currentClass in lst.slice(1)
                isInTail = true
                break

            if not isInTail
                found = true
                __mro__.push currentClass
                current = (for lst in current
                    if lst[0] is currentClass then lst.slice(1) else lst
                )

                break

        continue if found

        valid = true
        for i in current when i.length isnt 0
            valid = false
            break

        if valid
            return __mro__

inherit = (source, dest, clss, _super, ctx) ->
    for key, val of source
        [val, claz] = val
        # function => wrap it and call function with correct context and arguments
        if val instanceof Function
            dest[key] = do (key, claz) ->
                f = () ->
                    return _super.apply(ctx or @, [clss, key].concat(toArray arguments))
                # f.__name__ is needed for look up only because we're passing the key as name directly
                f.__name__ = key
                return f
        # no function => copy reference
        else
            dest[key] = val
    return

####################################################################################
window.Halo =
    config:
        staticKeys: ["@", "static"]
        constructorName: "__ctor__"

###
Halo.create([parents,] name, properties)
Creates a new class and returns it.
###
Halo.create = (parents, name, data) ->
    if not parents?
        parents = []
    # no parent list passed => shift params
    else if typeof parents is "string"
        data = name
        name = parents
        parents = []
    else if parents not instanceof Array
        parents = [parents]

    # data is a class
    if data instanceof Function
        clss = data
    # data is a hash
    else if data instanceof Object
        clss = classFromObject(name, data)
    else
        throw new Error "Invalid data passed:", data

    # MRO creation
    MRO = [clss].concat(mergeMRO ((parent.__mro__ or []) for parent in parents).concat([parents]))

    proto = clss.prototype
    selfStaticKeys  = Object.keys clss
    selfProtoKeys   = Object.keys proto

    staticVars  = {}
    protoVars   = {}

    reversedMRO = MRO.slice(1).reverse()
    # gather inheriting stuff from top to bottom (down the MRO)
    each reversedMRO, (claz, i) ->
        staticKeys  = Object.keys claz
        protoKeys   = Object.keys claz.prototype

        # save STATIC stuff
        for key in staticKeys when key not in selfStaticKeys
            staticVars[key] = [claz[key], claz]
        # save PROTO stuff
        for key in protoKeys when key not in selfProtoKeys
            protoVars[key] = [claz.prototype[key], claz]

        return true

    inherit(staticVars, clss, clss, _superStatic, clss)
    inherit(protoVars, proto, clss, _super, null)

    clss.__mro__ = MRO

    return clss
