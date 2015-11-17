Array::merge = Array::merge or (array) ->
    Array::push.apply(@, array)
    return @

Array::unique = Array::unique or () ->
    res = []
    for elem in @ when elem not in res
        res.push elem
    return res

Array::except = Array::except or (vals...) ->
    if vals.first instanceof Array
        vals = vals.first
    return (el for el in @ when el not in vals)

class window.Halo
    CLASS = @
    @__NULL__ = {}

    @config =
        staticKeys: ["@", "this", "static"]
        constructorName: "__ctor__"

    ############################################################################################################
    ############################################################################################################
    # PROTECTED
    @_getSuperClass: (instanceOrBaseClass, currentClass, n = 1) ->
        if instanceOrBaseClass.constructor.__class__?
            baseClass = instanceOrBaseClass.constructor.__class__
        else
            baseClass = instanceOrBaseClass
        mro = baseClass.__mro__
        return mro[mro.indexOf(currentClass) + n] or null

    # NOTE: context is either an instance or a class (depending on whether _super was called from static or instance context)
    # NOTE: the context will be applied to the next super function
    @_super: (args, context, clss, funcName) ->
        caller = args.callee.caller
        if caller.__cache__?
            return caller.__cache__.apply(context, args)

        if not funcName
            funcName = caller.__fn_name__
        superClass = CLASS._getSuperClass(context, clss)

        # called _super in constructor -> call super class'es constructor directly because it always exists
        # btw, this implies context is an instance. that's why it's returned
        if funcName is Halo.config.constructorName
            caller.__cache__ = superClass
            superClass.apply(context, args)
            return context
        else
            while superClass? and superClass[funcName] not instanceof Function and superClass::[funcName] not instanceof Function
                superClass = CLASS._getSuperClass(context, superClass)

            if superClass?
                if context.constructor.__class__?
                    method = superClass::[funcName]
                else
                    method = superClass[funcName]

                caller.__cache__ = method
                return method.apply(context, args)
        # not constructor and found no method in any super class
        return CLASS.__NULL__

    @_classFromObject: (name, obj) ->
        if obj.hasOwnProperty "constructor"
            ctorStr = obj.constructor
                .toString()
                .trim()
                .replace("function ", "function #{name}")
                .replace(/\n/g, "")
                .replace("return ", "")
            # remove closing '{' and 'return this;'
            ctorStr = ctorStr.substr(0, ctorStr.length - 1) + "return this; }"
        else
            ctorStr = "function #{name}(){ this._super.apply(this, arguments); return this; }"

        clss = eval("(#{ctorStr})")
        Object.defineProperties clss, {
            __class__:
                value: clss
                enumerable: false
                writable: true
            __name__:
                value: name
                enumerable: false
                writable: false
            __fn_name__:
                value: Halo.config.constructorName
                enumerable: false
                writable: true
            __mro__:
                value: []
                enumerable: false
                writable: true
        }

        # tell methods what name they have and what class they belong to
        # prototype vars
        for key, val of obj when key not in ["constructor"].concat(Halo.config.staticKeys)
            Object.defineProperties val, {
                __class__:
                    value: clss
                    enumerable: false
                    writable: true
                __fn_name__:
                    value: key
                    enumerable: false
                    writable: true
            }
            clss::[key] = val

        # static vars
        for key in Halo.config.staticKeys
            if (o = obj[key])?
                for key, val of o
                    if (typeof val is "object") or (typeof val is "function")
                        Object.defineProperties val, {
                            __class__:
                                value: clss
                                enumerable: false
                                writable: true
                            __fn_name__:
                                value: key
                                enumerable: false
                                writable: true
                        }
                    clss[key] = val

        # non-static
        clss::_super = () ->
            # NOTE: do not use the 'clss' var from closure but the one where the caller function is declared
            # NOTE: ('clss' would refer to the function of this)
            res = CLASS._super(arguments, @, arguments.callee.caller.__class__)
            if res isnt CLASS.__NULL__
                return res
            clss = arguments.callee.caller.__class__
            throw new Error("There is no 'this._super()' for the following function: #{arguments.callee.caller.__fn_name__} of #{(if clss.__fn_name__ isnt Halo.config.constructorName then clss.__fn_name__ else clss.__name__)} (in MRO of #{name})")

        # static
        clss._super = () ->
            res = CLASS._super(arguments, @, clss)
            if res isnt CLASS.__NULL__
                return res
            throw new Error("There is no 'this._super()' for the following static function: #{arguments.callee.caller.__fn_name__} of #{clss.__name__}")

        clss.prototype.__instanceof__ = (superClass) ->
            for mroClass in clss.__mro__
                if mroClass is superClass
                    return true
                # search in path to root of "normal coffeescript inheritance"
                while (mroClass = mroClass.__super__?.constructor)?
                    if mroClass is superClass
                        return true
            return false

        return clss

    # C3 merge() implementation (taken from https://github.com/nicolas-van/ring.js)
    @_mergeMRO: (toMerge) ->
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

            if found
                continue

            valid = true
            for i in current when i.length isnt 0
                valid = false
                break

            if valid
                return __mro__
        # return []

    ############################################################################################################
    ############################################################################################################
    # PUBLIC

    ###
    Halo.create([parents,] name, properties)
    Creates a new class and returns it.
    ###
    @create: (parents, name, data) ->
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
            clss = CLASS._classFromObject(name, data)
        else
            throw new Error "Invalid data passed:", data

        # MRO creation
        MRO = [clss].concat(CLASS._mergeMRO ((parent.__mro__ or []) for parent in parents).concat([parents]))

        # set __parents__ and __mro__
        Object.defineProperties clss, {
            __parents__:
                value: parents
                enumerable: false
                writable: false
        }

        if not clss.hasOwnProperty "__mro__"
            Object.defineProperties clss, {
                __mro__:
                    value: MRO
                    enumerable: false
                    writable: true
            }
        else
            clss.__mro__ = MRO

        # get list of all inherited methods create wrapper functions for calling _super() automatically
        # (NOTE: only works for coffeescript!)
        extendedMRO = []
        for claz, i in MRO
            extendedMRO.push claz
            if claz.__super__?
                superClass = claz
                while (superClass = superClass.__super__?.constructor)?
                    extendedMRO.push superClass

        # gather inheriting stuff from bottom to top (up the MRO)
        # first method found is put on 'clss' and directly linked to the match (so we skip checking classes that don't have the method themselves anyway)
        for superClass in extendedMRO
            do (superClass) ->
                # save STATIC stuff
                for key in Object.keys(superClass) when not clss[key]
                    f = superClass[key]
                    if not f.__class__
                        Object.defineProperties f, {
                            __class__:
                                value: superClass
                                enumerable: false
                                writable: true
                            __fn_name__:
                                value: key
                                enumerable: false
                                writable: true
                        }
                    clss[key] = f
                # save PROTO stuff
                for key in Object.keys(superClass.prototype) when not clss::[key]
                    f = superClass::[key]
                    if not f.__class__
                        Object.defineProperties f, {
                            __class__:
                                value: superClass
                                enumerable: false
                                writable: true
                            __fn_name__:
                                value: key
                                enumerable: false
                                writable: true
                        }
                    clss::[key] = f
                return true

        return clss

    @super: (funcName, instanceOrBaseClass, currentClass, args...) ->
        # instance => set caller to instance method
        if instanceOrBaseClass.constructor.__class__?
            args.callee =
                caller: currentClass::[funcName]
        else
            args.callee =
                caller: currentClass[funcName]
        return CLASS._super(args, instanceOrBaseClass, currentClass, funcName)
