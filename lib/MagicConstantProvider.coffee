{Point} = require 'atom'

AbstractProvider = require "./AbstractProvider"

module.exports =

##*
# Provides autocompletion for magic constants.
##
class MagicConstantProvider extends AbstractProvider
    ###*
     * @inheritdoc
     *
     * Variables are allowed inside double quoted strings (see also
     * {@link https://secure.php.net/manual/en/language.types.string.php#language.types.string.parsing}).
    ###
    disableForSelector: '.source.php .comment, .source.php .string.quoted.single'

    ###*
     * @inheritdoc
     *
     * "new" keyword or word starting with capital letter
    ###
    regex: /(__?(?:[A-Z]+_?_?)?)$/

    ###*
     * @inheritdoc
    ###
    getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix}) ->
        return [] if not @service

        prefix = @getPrefix(editor, bufferPosition)
        return [] unless prefix != null

        return @addSuggestions(prefix.trim())

    ###*
     * Returns suggestions available matching the given prefix.
     *
     * @param {string} prefix
     *
     * @return {array}
    ###
    addSuggestions: (prefix) ->
        suggestions = []

        constants = {
            '__LINE__'      : 'int',
            '__FILE__'      : 'string',
            '__DIR__'       : 'string',
            '__FUNCTION__'  : 'string',
            '__CLASS__'     : 'string',
            '__TRAIT__'     : 'string',
            '__METHOD__'    : 'string',
            '__NAMESPACE__' : 'string'
        }

        for name, type of constants
            suggestions.push
                type              : 'constant'
                text              : name
                leftLabel         : type
                replacementPrefix : prefix

        return suggestions
