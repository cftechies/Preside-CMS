component output=false {

// CONSTRUCTOR
	/**
	 * @configuredProviders.inject coldbox:setting:storageproviders
	 *
	 */
	public any function init( required any configuredProviders ) {
		_setConfiguredProviders( arguments.configuredProviders );

		return this;
	}

// PUBLIC API METHODS
	public array function listProviders() {
		return _getConfiguredProviders().keyArray();
	}

	public any function getProvider( required string id ) {
		var providers = _getConfiguredProviders();

		if ( providers.keyExists( arguments.id ) ) {
			return _createObject( cfcPath=providers[ arguments.id ].class );
		}

		throw( type="presidecms.storage.provider.not.found", message="The storage provider, [#arguments.id#], is not registered with the Storage Provider Service" );
	}

// PRIVATE HELPERS
	private any function _createObject( required string cfcPath ) {
		return CreateObject( "component", arguments.cfcPath ).init();
	}

// GETTERS AND SETTERS
	private any function _getConfiguredProviders() {
		return _configuredProviders;
	}
	private void function _setConfiguredProviders( required any configuredProviders ) {
		_configuredProviders = arguments.configuredProviders;
	}

}