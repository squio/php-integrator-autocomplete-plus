Utility = require './Utility'
AbstractProvider = require './AbstractProvider'

module.exports =

##*
# Provides autocompletion for class names (also after the new keyword and in use statements).
##
class ClassProvider extends AbstractProvider
    ###*
     * @inheritdoc
    ###
    regex: /(?:^|[^\$:>\w])(\\?[a-zA-Z_][a-zA-Z0-9_]*(?:\\[a-zA-Z_][a-zA-Z0-9_]*)*\\?)$/

    ###*
     # Regular expression matching class names after the new keyword.
    ###
    newRegex: /new\s+(\\?[a-zA-Z_][a-zA-Z0-9_]*(?:\\[a-zA-Z_][a-zA-Z0-9_]*)*\\?)?$/

    ###*
     # Regular expression matching class names after the use keyword.
    ###
    useRegex: /use\s+(\\?[a-zA-Z_][a-zA-Z0-9_]*(?:\\[a-zA-Z_][a-zA-Z0-9_]*)*\\?)?$/

    ###*
     # Regular expression matching class names after the namespace keyword.
    ###
    namespaceRegex: /namespace\s+(\\?[a-zA-Z_][a-zA-Z0-9_]*(?:\\[a-zA-Z_][a-zA-Z0-9_]*)*\\?)?$/

    ###*
     # Regular expression that extracts the classlike keyword and the class being extended from after the extends
     # keyword.
    ###
    extendsRegex: /([A-Za-z]+)\s+[a-zA-Z_0-9]+\s+extends\s+(\\?[a-zA-Z_][a-zA-Z0-9_]*(?:\\[a-zA-Z_][a-zA-Z0-9_]*)*)?$/

    ###*
     # Regular expression matching (only the last) interface name after the implements keyword.
    ###
    implementsRegex: /implements\s+(?:\\?[a-zA-Z_][a-zA-Z0-9_]*(?:\\[a-zA-Z_][a-zA-Z0-9_]*)*\\?,\s*)*(\\?[a-zA-Z_][a-zA-Z0-9_]*(?:\\[a-zA-Z_][a-zA-Z0-9_]*)*\\?)?$/

    ###*
     # Cache object to help improve responsiveness of autocompletion.
    ###
    listCache: null

    ###*
     # A list of disposables to dispose on deactivation.
    ###
    disposables: null

    ###*
     # Keeps track of a currently pending promise to ensure only one is active at any given time.
    ###
    pendingPromise: null

    ###*
     # Keeps track of a currently pending timeout to ensure only one is active at any given time..
    ###
    timeoutHandle: null

    ###*
     * @inheritdoc
    ###
    activate: (@service) ->
        {CompositeDisposable} = require 'atom'

        @disposables = new CompositeDisposable()

        @disposables.add(@service.onDidFinishIndexing(@onDidFinishIndexing.bind(this)))

    ###*
     * @inheritdoc
    ###
    deactivate: () ->
        if @disposables?
            @disposables.dispose()
            @disposables = null

    ###*
     * Called when reindexing successfully finishes.
     *
     * @param {Object} info
    ###
    onDidFinishIndexing: (info) ->
        # Only reindex a couple of seconds after the last reindex. This prevents constant refreshes being scheduled
        # while the user is still modifying the file. This is acceptable as this provider's data rarely changes and
        # it is fairly expensive to refresh the cache.
        if @timeoutHandle?
            clearTimeout(@timeoutHandle)
            @timeoutHandle = null

        @timeoutHandle = setTimeout ( =>
            @timeoutHandle = null
            @refreshCache()
        ), 5000

    ###*
     * Refreshes the internal cache. Returns a promise that resolves with the cache once it has been refreshed.
     *
     * @return {Promise}
    ###
    refreshCache: () ->
        successHandler = (classes) =>
            return @handleSuccessfulCacheRefresh(classes)

        failureHandler = () =>
            return @handleFailedCacheRefresh()

        if not @pendingPromise?
            @pendingPromise = @service.getClassList().then(successHandler, failureHandler)

        return @pendingPromise

    ###*
     * @param {Object} classes
     *
     * @return {Object}
    ###
    handleSuccessfulCacheRefresh: (classes) ->
        @pendingPromise = null

        return unless classes

        @listCache = classes

        return @listCache

    ###*
     * @return {Object}
    ###
    handleFailedCacheRefresh: () ->
        @pendingPromise = null

        return []

    ###*
     * Fetches a list of results that can be fed to the getSuggestions method.
     *
     * @return {Promise}
    ###
    fetchResults: () ->
        return new Promise (resolve, reject) =>
            if @listCache?
                resolve(@listCache)
                return

            return @refreshCache()

    ###*
     * @inheritdoc
    ###
    getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix}) ->
        return [] if not @service

        regexesToTry = {
            getExtendsSuggestions    : @extendsRegex
            getImplementsSuggestions : @implementsRegex
            getNamespaceSuggestions  : @namespaceRegex
            getUseSuggestions        : @useRegex
            getNewSuggestions        : @newRegex
            getClassSuggestions      : @regex
        }

        matches = null
        methodToUse = null

        for method, regex of regexesToTry
            matches = @getPrefixMatchesByRegex(editor, bufferPosition, regex)

            if matches?
                methodToUse = method
                break

        return [] if not methodToUse?

        successHandler = (classes) =>
            return [] unless classes

            return this[methodToUse].apply(this, [classes, matches])

        failureHandler = () =>
            # Just return no results.
            return []

        return @fetchResults().then(successHandler, failureHandler)

    ###*
     * Retrieves suggestions after the extends keyword.
     *
     * @param {Array} classes
     * @param {Array} matches
     *
     * @return {Array}
    ###
    getExtendsSuggestions: (classes, matches) ->
        prefix = if matches[2]? then matches[2] else ''

        suggestions = []

        if matches[1] == 'trait'
            return suggestions

        for name, element of classes
            if element.type != matches[1] or element.isFinal
                continue # Interfaces can only extend interfaces and classes can only extend classes.

            suggestion = @getSuggestionForData(element)
            suggestion.replacementPrefix = prefix

            @applyAutomaticImportData(suggestion, prefix)

            suggestions.push(suggestion)

        return suggestions

    ###*
     * Retrieves suggestions after the implements keyword.
     *
     * @param {Array} classes
     * @param {Array} matches
     *
     * @return {Array}
    ###
    getImplementsSuggestions: (classes, matches) ->
        prefix = if matches[1]? then matches[1] else ''

        suggestions = []

        for name, element of classes
            if element.type != 'interface'
                continue

            suggestion = @getSuggestionForData(element)
            suggestion.replacementPrefix = prefix

            @applyAutomaticImportData(suggestion, prefix)

            suggestions.push(suggestion)

        return suggestions

    ###*
     * Retrieves suggestions for namespace names.
     *
     * @param {Array} classes
     * @param {Array} matches
     *
     * @return {Array}
    ###
    getNamespaceSuggestions: (classes, matches) ->
        prefix = if matches[1]? then matches[1] else ''

        suggestions = []

        for name, element of classes
            suggestion = @getSuggestionForData(element)
            suggestion.type = 'import'
            suggestion.replacementPrefix = prefix

            suggestions.push(suggestion)

        return suggestions

    ###*
     * Retrieves suggestions for use statements.
     *
     * @param {Array} classes
     * @param {Array} matches
     *
     * @return {Array}
    ###
    getUseSuggestions: (classes, matches) ->
        prefix = if matches[1]? then matches[1] else ''

        suggestions = []

        for name, element of classes
            suggestion = @getSuggestionForData(element)
            suggestion.type = 'import'
            suggestion.replacementPrefix = prefix

            suggestions.push(suggestion)

        return suggestions

    ###*
     * Retrieves suggestions for class names after the new keyword.
     *
     * @param {Array} classes
     * @param {Array} matches
     *
     * @return {Array}
    ###
    getNewSuggestions: (classes, matches) ->
        prefix = if matches[1]? then matches[1] else ''

        suggestions = []

        for name, element of classes
            if element.type != 'class' or element.isAbstract
                continue # Not possible to instantiate these.

            suggestion = @getSuggestionForData(element)
            suggestion.replacementPrefix = prefix

            @applyAutomaticImportData(suggestion, prefix)

            suggestions.push(suggestion)

        return suggestions

    ###*
     * Retrieves suggestions for classlike names.
     *
     * @param {Array} classes
     * @param {Array} matches
     *
     * @return {Array}
    ###
    getClassSuggestions: (classes, matches) ->
        prefix = if matches[1]? then matches[1] else ''

        suggestions = []

        for name, element of classes
            suggestion = @getSuggestionForData(element)
            suggestion.replacementPrefix = prefix

            @applyAutomaticImportData(suggestion, prefix)

            suggestions.push(suggestion)

        return suggestions

    ###*
     * @param {Object} data
     *
     * @return {Array}
    ###
    getSuggestionForData: (data) ->
        suggestionData =
            text               : data.name
            type               : if data.type == 'trait' then 'mixin' else 'class'
            description        : if data.isBuiltin then 'Built-in PHP structural data.' else data.shortDescription
            leftLabel          : data.type
            descriptionMoreURL : if data.isBuiltin then @config.get('php_documentation_base_urls').classes + data.name else null
            className          : if data.isDeprecated then 'php-integrator-autocomplete-plus-strike' else ''
            displayText        : data.name
            data               : {}

    ###*
     * @param {Object} suggestion
     * @param {String} prefix
    ###
    applyAutomaticImportData: (suggestion, prefix) ->
        hasLeadingSlash = false

        if prefix.length > 0 and prefix[0] == '\\'
            hasLeadingSlash = true
            prefix = prefix.substring(1, prefix.length)

        prefixParts = prefix.split('\\')
        partsToSlice = (prefixParts.length - 1)

        fqcn = suggestion.text

        # We try to add an import that has only as many parts of the namespace as needed, for example, if the user
        # types 'Foo\Class' and confirms the suggestion 'My\Foo\Class', we add an import for 'My\Foo' and leave the
        # user's code at 'Foo\Class' as a relative import. We only add the full 'My\Foo\Class' if the user were to
        # type just 'Class' and then select 'My\Foo\Class' (i.e. we remove as many segments from the suggestion
        # as the user already has in his code).
        suggestion.data.nameToImport = null

        if hasLeadingSlash
            suggestion.text = '\\' + fqcn

        else
            # Don't try to add use statements for class names that the user wants to make absolute by adding a
            # leading slash.
            suggestion.text = @getNameToInsert(fqcn, partsToSlice)
            suggestion.data.nameToImport = @getNameToImport(fqcn, partsToSlice)

    ###*
     * Returns the name to insert into the buffer.
     *
     * @param {String} fqcn            The FQCN of the class that needs to be imported.
     * @param {Number} partsToShiftOff The amount of parts to leave extra for the class name. For example, a value of 1
     *                                     will return B\C instead of A\B\C. A value of 0 will return just C.
     *
     * @return {String|null}
    ###
    getNameToInsert: (fqcn, extraPartsToMaintain) ->
        if fqcn[0] == '\\'
            fqcn = fqcn.substring(1)

        fqcnParts = fqcn.split('\\')

        if true
            nameToUseParts = fqcnParts.slice(-extraPartsToMaintain - 1)

        return nameToUseParts.join('\\')

    ###*
     * Returns the name to import via a use statement.
     *
     * @param {String} fqcn          The FQCN of the class that needs to be imported.
     * @param {Number} partsToPopOff The amount of parts to leave off of the end of the class name. For example, a
     *                               value of 1 will return A\B instead of A\B\C.
     *
     * @return {String|null}
    ###
    getNameToImport: (fqcn, partsToPopOff) ->
        if fqcn[0] == '\\'
            fqcn = fqcn.substring(1)

        fqcnParts = fqcn.split('\\')

        if partsToPopOff > 0
            fqcnParts = fqcnParts.slice(0, -partsToPopOff)

        return fqcnParts.join('\\')

    ###*
     * Called when the user confirms an autocompletion suggestion.
     *
     * @param {TextEditor} editor
     * @param {Position}   triggerPosition
     * @param {Object}     suggestion
    ###
    onDidInsertSuggestion: ({editor, triggerPosition, suggestion}) ->
        return unless suggestion.data?.nameToImport
        return unless @config.get('automaticallyAddUseStatements')

        successHandler = (currentClassName) =>
            if currentClassName
                currentNamespaceParts = currentClassName.split('\\')
                currentNamespaceParts.pop()

                currentNamespace = currentNamespaceParts.join('\\')

                if suggestion.data.nameToImport.indexOf(currentNamespace) == 0
                     nameToImportRelativeToNamespace = suggestion.displayText.substr(currentNamespace.length + 1)

                     # If a user is in A\B and wants to import A\B\C\D, we don't need to add a use statement if he is typing
                     # C\D, as it will be relative, but we will need to add one when he typed just D as it won't be
                     # relative.
                     return if nameToImportRelativeToNamespace.split('\\').length == suggestion.text.split('\\').length

            editor.transact () =>
                linesAdded = Utility.addUseClass(editor, suggestion.data.nameToImport, @config.get('insertNewlinesForUseStatements'))

        failureHandler = () ->
            # Do nothing.

        @service.determineCurrentClassName(editor, triggerPosition).then(successHandler, failureHandler)
