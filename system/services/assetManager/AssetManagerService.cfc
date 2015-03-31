/**
 * @singleton true
 *
 */
component {

// CONSTRUCTOR
	/**
	 * @storageProvider.inject            assetStorageProvider
	 * @temporaryStorageProvider.inject   tempStorageProvider
	 * @assetTransformer.inject           AssetTransformer
	 * @tikaWrapper.inject                TikaWrapper
	 * @systemConfigurationService.inject systemConfigurationService
	 * @configuredDerivatives.inject      coldbox:setting:assetManager.derivatives
	 * @configuredTypesByGroup.inject     coldbox:setting:assetManager.types
	 * @configuredFolders.inject          coldbox:setting:assetManager.folders
	 * @assetDao.inject                   presidecms:object:asset
	 * @assetVersionDao.inject            presidecms:object:asset_version
	 * @folderDao.inject                  presidecms:object:asset_folder
	 * @derivativeDao.inject              presidecms:object:asset_derivative
	 * @assetMetaDao.inject               presidecms:object:asset_meta
	 */
	public any function init(
		  required any    storageProvider
		, required any    temporaryStorageProvider
		, required any    assetTransformer
		, required any    tikaWrapper
		, required any    systemConfigurationService
		, required any    assetDao
		, required any    assetVersionDao
		, required any    folderDao
		, required any    derivativeDao
		, required any    assetMetaDao
		,          struct configuredDerivatives={}
		,          struct configuredTypesByGroup={}
		,          struct configuredFolders={}
	) {
 		_setAssetDao( arguments.assetDao );
 		_setAssetVersionDao( arguments.assetVersionDao );
		_setFolderDao( arguments.folderDao );

		_setupSystemFolders( arguments.configuredFolders );

		_setStorageProvider( arguments.storageProvider );
		_setAssetTransformer( arguments.assetTransformer );
		_setTemporaryStorageProvider( arguments.temporaryStorageProvider );
		_setTikaWrapper( arguments.tikaWrapper );
		_setSystemConfigurationService( arguments.systemConfigurationService );

		_setConfiguredDerivatives( arguments.configuredDerivatives );
		_setupConfiguredFileTypesAndGroups( arguments.configuredTypesByGroup );
		_setDerivativeDao( arguments.derivativeDao );
		_setAssetMetaDao( arguments.assetMetaDao );

		return this;
	}

// PUBLIC API METHODS
	public string function addFolder( required string label, string parent_folder="" ) {
		if ( not Len( Trim( arguments.parent_folder ) ) ) {
			arguments.parent_folder = getRootFolderId();
		} else {
			if ( isSystemFolder( arguments.parent_folder ) ) {
				throw( type="PresideCMS.AssetManager.invalidOperation", message="You cannot add child folders to system folders." );
			}
		}

		return _getFolderDao().insertData( arguments );
	}

	public boolean function editFolder( required string id, required struct data ) {
		if ( arguments.data.keyExists( "parent_folder" ) && not Len( Trim( arguments.data.parent_folder ) ) ) {
			arguments.data.parent_folder = getRootFolderId();
		}

		return _getFolderDao().updateData(
			  id   = arguments.id
			, data = arguments.data
		);
	}

	public query function getFolder( required string id, boolean includeHidden=false ) {
		var filter = { id=arguments.id };
		var extra  = [];
		if ( !includeHidden ) {
			extra.append( _getExcludeHiddenFilter() );
		}

		return _getFolderDao().selectData( filter=filter, extraFilters=extra );
	}

	public query function getFolderAncestors( required string id, boolean includeChildFolder=false ) {
		var folder        = getFolder( id=arguments.id );
		var ancestors     = QueryNew( folder.columnList );
		var ancestorArray = [];

		if ( arguments.includeChildFolder ){
			ancestorArray.append( folder );
		}

		while( folder.recordCount ){
			if ( not Len( Trim( folder.parent_folder ) ) ) {
				break;
			}
			folder = getFolder( id=folder.parent_folder );
			if ( folder.recordCount ) {
				ArrayAppend( ancestorArray, folder );
			}
		}

		for( var i=ancestorArray.len(); i gt 0; i-- ){
			for( folder in ancestorArray[i] ) {
				QueryAddRow( ancestors, folder );
			}
		}

		return ancestors;
	}

	public struct function getCascadingFolderSettings( required string id, required array settings ) {
		var folder            = getFolder( arguments.id );
		var collectedSettings = {};

		for( var setting in arguments.settings ) {
			if ( Len( Trim( folder[ setting ] ?: "" ) ) ) {
				collectedSettings[ setting ] = folder[ setting ];
			}
		}

		if ( StructCount( collectedSettings ) == arguments.settings.len() ) {
			return collectedSettings;
		}

		for( var folder in getFolderAncestors( arguments.id ) ) {
			for( var setting in arguments.settings ) {
				if ( !collectedSettings.keyExists( setting ) && Len( Trim( folder[ setting ] ?: "" ) ) ) {
					collectedSettings[ setting ] = folder[ setting ];
					if ( StructCount( collectedSettings ) == arguments.settings.len() ) {
						return collectedSettings;
					}
				}
			}
		}

		return collectedSettings;
	}

	public query function getAllFoldersForSelectList( string parentString="/ ", string parentFolder="", query finalQuery ) {
		var folders = _getFolderDao().selectData(
			  selectFields = [ "id", "label" ]
			, filter       = { parent_folder = Len( Trim( arguments.parentFolder ) ) ? arguments.parentFolder : getRootFolderId() }
			, orderBy      = "label"
		);

		if ( !StructKeyExists( arguments, "finalQuery" ) ) {
			arguments.finalQuery = QueryNew( 'id,label' );
		}

		for ( var folder in folders ) {
			QueryAddRow( finalQuery, { id=folder.id, label=parentString & folder.label } );

			finalQuery = getAllFoldersForSelectList( parentString & folder.label & " / ", folder.id, finalQuery );
		}

		return finalQuery;
	}

	public array function getFolderTree( string parentFolder="", string parentRestriction="none", permissionContext=[] ) {
		var tree    = [];
		var folders = _getFolderDao().selectData(
			  selectFields = [ "id", "label", "access_restriction", "is_system_folder" ]
			, filter       = Len( Trim( arguments.parentFolder ) ) ? { parent_folder =  arguments.parentFolder } : { id = getRootFolderId() }
			, extraFilters = [ _getExcludeHiddenFilter() ]
			, orderBy      = "label"
		);

		for ( var folder in folders ) {
			if ( folder.access_restriction == "inherit" ) {
				folder.access_restriction = arguments.parentRestriction;
			}
			folder.permissionContext = arguments.permissionContext;
			folder.permissionContext.prepend( folder.id );

			folder.append( { children=getFolderTree( folder.id, folder.access_restriction, folder.permissionContext ) } );

			tree.append( folder );
		}

		return tree;
	}

	public array function expandTypeList( required array types, boolean prefixExtensionsWithPeriod=false ) {
		var expanded = [];
		var types    = _getTypes();

		for( var typeName in arguments.types ){
			if ( types.keyExists( typeName ) ) {
				expanded.append( typeName );
			} else {
				for( var typeName in listTypesForGroup( typeName ) ){
					expanded.append( typeName );
				}
			}
		}

		if ( arguments.prefixExtensionsWithPeriod ) {
			for( var i=1; i <= expanded.len(); i++ ){
				expanded[i] = "." & expanded[i];
			}
		}

		return expanded;
	}

	public struct function getAssetsForGridListing(
		  numeric startRow    = 1
		, numeric maxRows     = 10
		, string  orderBy     = ""
		, string  searchQuery = ""
		, string  folder      = ""

	) {

		var result       = { totalRecords = 0, records = "" };
		var parentFolder = Len( Trim( arguments.folder ) ) ? arguments.folder : getRootFolderId();
		var args         = {
			  startRow = arguments.startRow
			, maxRows  = arguments.maxRows
			, orderBy  = arguments.orderBy
		};

		if ( Len( Trim( arguments.searchQuery ) ) ) {
			args.filter       = "asset_folder = :asset_folder and title like :q";
			args.filterParams = { asset_folder=parentFolder, q = { type="varchar", value="%" & arguments.searchQuery & "%" } };
		} else {
			args.filter = { asset_folder = parentFolder };
		}

		result.records = _getAssetDao().selectData( argumentCollection = args );

		if ( arguments.startRow eq 1 and result.records.recordCount lt arguments.maxRows ) {
			result.totalRecords = result.records.recordCount;
		} else {
			args.selectFields = [ "count( * ) as nRows" ];
			StructDelete( args, "startRow" );
			StructDelete( args, "maxRows" );

			result.totalRecords = _getAssetDao().selectData( argumentCollection = args ).nRows;
		}

		return result;
	}

	public array function getAssetsForAjaxSelect( array ids=[], string searchQuery="", array allowedTypes=[], numeric maxRows=100 ) {
		var assetDao    = _getAssetDao();
		var filter      = "( asset.asset_folder != :asset_folder )";
		var params      = { asset_folder = _getTrashFolderId() };
		var types       = _getTypes();
		var records     = "";
		var result      = [];

		if ( arguments.ids.len() ) {
			filter &= " and ( asset.id in (:id) )";
			params.id = { value=ArrayToList( arguments.ids ), list=true };
		}
		if ( arguments.allowedTypes.len() ) {
			params.asset_type = { value="", list=true };

			for( var typeName in expandTypeList( arguments.allowedTypes ) ){
				params.asset_type.value = ListAppend( params.asset_type.value, typeName );
			}
			if ( Len( Trim( params.asset_type.value ) ) ){
				filter &= " and ( asset.asset_type in (:asset_type) )";
			} else {
				params.delete( "asset_type" );
			}
		}
		if ( Len( Trim( arguments.searchQuery ) ) ) {
			filter &= " and ( asset.title like (:title) )";
			params.title = "%#arguments.searchQuery#%";
		}

		if ( params.isEmpty() ) {
			filter = {};
		}

		records = assetDao.selectData(
			  selectFields = [ "asset.id as value", "asset.${labelfield} as text", "asset_folder.${labelfield} as folder" ]
			, filter       = filter
			, filterParams = params
			, maxRows      = arguments.maxRows
			, orderBy      = "asset.datemodified desc"
		);

		for( var record in records ){
			record.folder = record.folder ?: "";
			result.append( record );
		}

		return result;
	}

	public string function getPrefetchCachebusterForAjaxSelect( array allowedTypes=[] ) {
		var filter  = "( asset.asset_folder != :asset_folder )";
		var params  = { asset_folder = _getTrashFolderId() };
		var records = "";

		if ( arguments.allowedTypes.len() ) {
			params.asset_type = { value="", list=true };

			for( var typeName in expandTypeList( arguments.allowedTypes ) ){
				params.asset_type.value = ListAppend( params.asset_type.value, typeName );
			}
			if ( Len( Trim( params.asset_type.value ) ) ){
				filter &= " and ( asset.asset_type in (:asset_type) )";
			} else {
				params.delete( "asset_type" );
			}
		}

		records = _getAssetDao().selectData(
			  selectFields = [ "Max( asset.datemodified ) as lastmodified" ]
			, filter       = filter
			, filterParams = params
		);

		return records.recordCount ? Hash( records.lastmodified ) : Hash( Now() );
	}

	public boolean function trashFolder( required string id ) {
		var folder = getFolder( arguments.id );

		if ( !folder.recordCount || ( IsBoolean( folder.is_system_folder ?: "" ) && folder.is_system_folder ) ) {
			return false;
		}

		return _getFolderDao().updateData( id = arguments.id, data = {
			  parent_folder  = _getTrashFolderId()
			, label          = CreateUUId()
			, original_label = folder.label
		} );
	}

	public string function uploadTemporaryFile( required string fileField ) {
		var tmpId         = CreateUUId();
		var storagePath   = "/" & tmpId & "/";
		var uploadedFile  = "";
		var transientPath = "";

		try {
			uploadedFile = FileUpload(
				  destination  = GetTempDirectory()
				, fileField    = arguments.filefield
				, nameConflict = "MakeUnique"
			);
		} catch( any e ) {
			return "";
		}

		storagePath  &= uploadedFile.serverFile;
		transientPath = uploadedFile.serverDirectory & "/" & uploadedFile.serverFile;

		_getTemporaryStorageProvider().putObject(
			  object = transientPath
			, path   = storagePath
		);

		FileDelete( transientPath );

		return tmpId;
	}

	public void function deleteTemporaryFile( required string tmpId ) {
		var details = getTemporaryFileDetails( arguments.tmpId );
		if ( Len( Trim( details.path ?: "" ) ) ) {
			_getTemporaryStorageProvider().deleteObject( details.path );
		}
	}

	public struct function getTemporaryFileDetails( required string tmpId, boolean includeMeta=false ) {
		var storageProvider = _getTemporaryStorageProvider();
		var files           = storageProvider.listObjects( "/#arguments.tmpId#/" );
		var details         = {};

		for( var file in files ) {
			if ( arguments.includeMeta ) {
				details = _getTikaWrapper().getMetadata( storageProvider.getObject( file.path ) );
			}

			StructAppend( details, file );

			details.title = details.title ?: ( details.name ?: "" );

			break;
		}

		return details;
	}

	public binary function getTemporaryFileBinary( required string tmpId ) {
		var details = getTemporaryFileDetails( arguments.tmpId );

		return _getTemporaryStorageProvider().getObject( details.path ?: "" );
	}

	public string function saveTemporaryFileAsAsset( required string tmpId, string folder, struct assetData = {} ) {
		var asset        = Duplicate( arguments.assetData );
		var fileDetails  = getTemporaryFileDetails( arguments.tmpId );

		if ( StructIsEmpty( fileDetails ) ) {
			return "";
		}

		asset.append( fileDetails, false );

		var fileBinary  = _getTemporaryStorageProvider().getObject( fileDetails.path );
		var newId       = addAsset( fileBinary, fileDetails.name, arguments.folder, asset );

		deleteTemporaryFile( arguments.tmpId );

		return newId;
	}

	public string function addAsset( required binary fileBinary, required string fileName, required string folder, struct assetData={} ) {
		var fileTypeInfo = getAssetType( filename=arguments.fileName, throwOnMissing=true );
		var newFileName  = "/uploaded/" & CreateUUId() & "." & fileTypeInfo.extension;
		var asset        = Duplicate( arguments.assetData );

		_getStorageProvider().putObject(
			  object = arguments.fileBinary
			, path   = newFileName
		);

		asset.asset_folder     = resolveFolderId( arguments.folder );
		asset.asset_type       = fileTypeInfo.typeName;
		asset.storage_path     = newFileName;
		asset.size             = asset.size  ?: Len( arguments.fileBinary );
		asset.title            = asset.title ?: "";

		if ( !Len( Trim( asset.title ) ) ) {
			asset.title = arguments.fileName;
		}

		if ( _autoExtractDocumentMeta() ) {
			asset.raw_text_content = _getTikaWrapper().getText( arguments.fileBinary );
		}

		if ( not Len( Trim( asset.asset_folder ) ) ) {
			asset.asset_folder = getRootFolderId();
		}

		var newId = _getAssetDao().insertData( data=asset );

		if ( _autoExtractDocumentMeta() ) {
			_saveAssetMetaData( assetId=newId, metaData=_getTikaWrapper().getMetaData( arguments.fileBinary ) );
		}

		return newId;
	}

	public boolean function addAssetVersion( required string assetId, required binary fileBinary, required string fileName, boolean makeActive=true  ) {
		var fileTypeInfo = getAssetType( filename=arguments.fileName, throwOnMissing=true );
		var newFileName  = "/uploaded/" & CreateUUId() & "." & fileTypeInfo.extension;
		var versionId    = "";
		var assetVersion = {
			  asset        = arguments.assetId
			, asset_type   = fileTypeInfo.typeName
			, storage_path = newFileName
			, size         = Len( arguments.fileBinary )
			, version_number = _getNextAssetVersionNumber( arguments.assetId )
		};

		if ( _autoExtractDocumentMeta() ) {
			assetVersion.raw_text_content = _getTikaWrapper().getText( arguments.fileBinary );
		}

		_getStorageProvider().putObject( object = arguments.fileBinary, path = newFileName );

		versionId = _getAssetVersionDao().insertData( data=assetVersion );

		if ( arguments.makeActive ) {
			makeVersionActive( arguments.assetId, versionId );
		}

		if ( _autoExtractDocumentMeta() ) {
			_saveAssetMetaData(
				  assetId   = arguments.assetId
				, versionId = versionId
				, metaData  = _getTikaWrapper().getMetaData( arguments.fileBinary )
			);
		}

		return true;
	}

	public string function getRawTextContent( required string assetId ) {
		var asset = getAsset( id=arguments.assetId, selectFields=[ "asset_type", "raw_text_content" ] );

		if ( asset.recordCount && asset.asset_type != "image" ) {
			if ( Len( Trim( asset.raw_text_content ) ) ) {
				return asset.raw_text_content;
			}
		}

		if ( _autoExtractDocumentMeta() ) {
			var fileBinary = getAssetBinary( arguments.assetId );
			if ( !IsNull( fileBinary ) ) {
				var rawText = _getTikaWrapper().getText( fileBinary );
				if ( Len( Trim( rawText ) ) ) {
					_getAssetDao().updateData( id=arguments.assetId, data={ raw_text_content=rawText } );
				}

				return rawText;
			}
		}

		return "";
	}

	public boolean function editAsset( required string id, required struct data ) {
		return _getAssetDao().updateData( id=arguments.id, data=arguments.data );
	}

	public struct function getAssetType( string filename="", string name=ListLast( arguments.fileName, "." ), boolean throwOnMissing=false ) {
		var types = _getTypes();

		if ( StructKeyExists( types, arguments.name ) ) {
			return types[ arguments.name ];
		}

		if ( not arguments.throwOnMissing ) {
			return {};
		}

		throw(
			  type    = "assetManager.fileTypeNotFound"
			, message = "The file type, [#arguments.name#], could not be found"
		);
	}

	public array function listTypesForGroup( required string groupName ) {
		var groups = _getGroups();

		return groups[ arguments.groupName ] ?: [];
	}

	public query function getAsset( required string id, array selectFields=[], boolean throwOnMissing=false ) {
		var asset = Len( Trim( arguments.id ) ) ? _getAssetDao().selectData( id=arguments.id, selectFields=arguments.selectFields ) : QueryNew('');

		if ( asset.recordCount or not throwOnMissing ) {
			return asset;
		}

		throw(
			  type    = "AssetManager.assetNotFound"
			, message = "Asset with id [#arguments.id#] not found"
		);
	}

	public binary function getAssetBinary( required string id, boolean throwOnMissing=false ) {
		var asset = getAsset( id = arguments.id, throwOnMissing = arguments.throwOnMissing );
		var assetBinary = "";

		if ( asset.recordCount ) {
			return _getStorageProvider().getObject( asset.storage_path );
		}
	}

	public string function getAssetEtag( required string id, string derivativeName="", boolean throwOnMissing=false ) output="false" {
		var asset = "";

		if ( Len( Trim( arguments.derivativeName ) ) ) {
			asset = getAssetDerivative(
				  assetId        = arguments.id
				, derivativeName = arguments.derivativeName
				, throwOnMissing = arguments.throwOnMissing
			);
		} else {
			asset = getAsset( id = arguments.id, throwOnMissing = arguments.throwOnMissing );
		}

		if ( asset.recordCount ) {
			var assetInfo = _getStorageProvider().getObjectInfo( asset.storage_path );
			var etag      = LCase( Hash( SerializeJson( assetInfo ) ) )

			return Left( etag, 8 );
		}

		return "";
	}

	public boolean function trashAsset( required string id ) {
		var assetDao    = _getAssetDao();
		var asset       = assetDao.selectData( id=arguments.id, selectFields=[ "storage_path", "title" ] );
		var trashedPath = "";

		if ( !asset.recordCount ) {
			return false;
		}

		trashedPath = _getStorageProvider().softDeleteObject( asset.storage_path );

		return assetDao.updateData( id=arguments.id, data={
			  trashed_path   = trashedPath
			, title          = CreateUUId()
			, original_title = asset.title
			, asset_folder   = _getTrashFolderId()
		} );
	}

	public query function getAssetDerivative( required string assetId, required string derivativeName ) {
		var derivativeDao = _getDerivativeDao();
		var derivative    = "";
		var signature     = getDerivativeConfigSignature( arguments.derivativeName );
		var selectFilter  = { "asset_derivative.asset" = arguments.assetId, "asset_derivative.label" = arguments.derivativeName & signature };
		var lockName      = "getAssetDerivative( #assetId#, #arguments.derivativeName# )";

		lock type="readonly" name=lockName timeout=5 {
			derivative = derivativeDao.selectData( filter=selectFilter );
			if ( derivative.recordCount ) {
				return derivative;
			}
		}

		lock type="exclusive" name=lockName timeout=120 {
			createAssetDerivative( assetId=arguments.assetId, derivativeName=arguments.derivativeName );

			return derivativeDao.selectData( filter=selectFilter );
		}
	}

	public binary function getAssetDerivativeBinary( required string assetId, required string derivativeName ) {
		var derivative = getAssetDerivative( assetId = arguments.assetId, derivativeName = arguments.derivativeName );

		if ( derivative.recordCount ) {
			return _getStorageProvider().getObject( derivative.storage_path );
		}
	}

	public string function createAssetDerivativeWhenNotExists(
		  required string assetId
		, required string derivativeName
		,          array  transformations = _getPreconfiguredDerivativeTransformations( arguments.derivativeName )
	) {
		var derivativeDao = _getDerivativeDao();
		var signature     = getDerivativeConfigSignature( arguments.derivativeName );
		var selectFilter  = { "asset_derivative.asset" = arguments.assetId, "asset_derivative.label" = arguments.derivativeName & signature };

		if ( !derivativeDao.dataExists( filter=selectFilter ) ) {
			return createAssetDerivative( argumentCollection = arguments );
		}
	}

	public string function createAssetDerivative(
		  required string assetId
		, required string derivativeName
		,          array  transformations = _getPreconfiguredDerivativeTransformations( arguments.derivativeName )
	) {
		var signature       = getDerivativeConfigSignature( arguments.derivativeName );
		var asset           = getAsset( id=arguments.assetId, throwOnMissing=true );
		var assetBinary     = getAssetBinary( id=arguments.assetId, throwOnMissing=true );
		var filename        = ListLast( asset.storage_path, "/" );
		var fileext         = ListLast( filename, "." );
		var derivativeSlug  = ReReplace( arguments.derivativeName, "\W", "_", "all" );
		var storagePath     = "/derivatives/#derivativeSlug#/#filename#";

		for( var transformation in transformations ) {
			if ( not Len( Trim( transformation.inputFileType ?: "" ) ) or transformation.inputFileType eq fileext ) {
				assetBinary = _applyAssetTransformation(
					  assetBinary          = assetBinary
					, transformationMethod = transformation.method ?: ""
					, transformationArgs   = transformation.args   ?: {}
				);

				if ( Len( Trim( transformation.outputFileType ?: "" ) ) ) {
					storagePath = ReReplace( storagePath, "\.#fileext#$", "." & transformation.outputFileType );
					fileext = transformation.outputFileType;
				}
			}
		}
		var assetType = getAssetType( filename=storagePath, throwOnMissing=true );

		_getStorageProvider().putObject( assetBinary, storagePath );

		return _getDerivativeDao().insertData( {
			  asset_type   = assetType.typeName
			, asset        = arguments.assetId
			, label        = arguments.derivativeName & signature
			, storage_path = storagePath
		} );
	}

	public struct function getAssetPermissioningSettings( required string assetId ) {
		var asset    = getAsset( arguments.assetId );
		var settings = {
			  contextTree       = [ arguments.assetId ] //ListToArray( ValueList( folders.id ) ) };
			, restricted        = false
			, fullLoginRequired = false
		}

		if ( !asset.recordCount ){ return settings; }

		var folders = getFolderAncestors( asset.asset_folder, true );

		for( var folder in folders ){ settings.contextTree.append( folder.id ); }

		if ( asset.access_restriction != "inherit" ) {
			settings.restricted        = asset.access_restriction == "full";
			settings.fullLoginRequired = IsBoolean( asset.full_login_required ) && asset.full_login_required;

			return settings;
		}

		for( var folder in folders ) {
			if ( folder.access_restriction != "inherit" ) {
				settings.restricted        = folder.access_restriction == "full";
				settings.fullLoginRequired = IsBoolean( folder.full_login_required ) && folder.full_login_required;

				return settings;
			}
		}

		return settings;
	}

	public boolean function isDerivativePubliclyAccessible( required string derivative ) {
		var derivatives = _getConfiguredDerivatives();

		return ( derivatives[ arguments.derivative ].permissions ?: "inherit" ) == "public";
	}

	public string function getDerivativeConfigSignature( required string derivative ) {
		var derivatives = _getConfiguredDerivatives();

		if ( derivatives.keyExists( arguments.derivative ) ) {
			if ( !derivatives[ arguments.derivative ].keyExists( "signature" ) ) {
				derivatives[ arguments.derivative ].signature = LCase( Hash( SerializeJson( derivatives[ arguments.derivative ] ) ) );
			}

			return derivatives[ arguments.derivative ].signature;
		}

		return "";
	}

	public boolean function isSystemFolder( required string folderId ) {
		return _getFolderDao().dataExists( filter={ id=arguments.folderId, is_system_folder=true } );
	}

	public string function resolveFolderId( required string folderId ) {
		var folder = _getFolderDao().selectData( selectFields=[ "id" ], filter={ system_folder_key=arguments.folderId } );

		if ( folder.recordCount ) {
			return folder.id;
		}

		return arguments.folderId;
	}

	public boolean function makeVersionActive( required string assetId, required string versionId ) {
		var versionToMakeActive = _getAssetVersionDao().selectData(
			  id           = arguments.versionId
			, selectFields = [
				  "storage_path"
				, "size"
				, "asset_type"
				, "raw_text_content"
				, "created_by"
				, "updated_by"
			]
		);

		if ( versionToMakeActive.recordCount ) {
			return _getAssetDao().updateData( id=arguments.assetId, data={
				  active_version   = arguments.versionId
				, storage_path     = versionToMakeActive.storage_path
				, size             = versionToMakeActive.size
				, asset_type       = versionToMakeActive.asset_type
				, raw_text_content = versionToMakeActive.raw_text_content
				, created_by       = versionToMakeActive.created_by
				, updated_by       = versionToMakeActive.updated_by
			} );
		}

		return false;
	}

	public query function getAssetVersions( required string assetId, array selectFields=[] ) {
		return _getAssetVersionDao().selectData(
			  filter       = { asset = arguments.assetId }
			, orderBy      = "version_number"
			, selectfields = arguments.selectfields
		);
	}

// PRIVATE HELPERS
	private void function _setupSystemFolders( required struct configuredFolders ) {
		var dao         = _getFolderDao();
		var rootFolder  = dao.selectData( selectFields=[ "id" ], filter="parent_folder is null and label = :label", filterParams={ label="$root" } );
		var trashFolder = dao.selectData( selectFields=[ "id" ], filter="parent_folder is null and label = :label", filterParams={ label="$recycle_bin" } );

		if ( rootFolder.recordCount ) {
			_setRootFolderId( rootFolder.id );
		} else {
			_setRootFolderId( dao.insertData( data={ label="$root" } ) );
		}

		if ( trashFolder.recordCount ) {
			_setTrashFolderId( trashFolder.id );
		} else {
			_setTrashFolderId( dao.insertData( data={ label="$recycle_bin" } ) );
		}

		for( var folderId in arguments.configuredFolders ){
			_setupConfiguredSystemFolder( folderId, arguments.configuredFolders[ folderId ], getRootFolderId() );
		}
	}

	private void function _setupConfiguredSystemFolder( required string id, required struct settings, required string parentId ) {
		var dao            = _getFolderDao();
		var existingRecord = dao.selectData( selectfields=[ "id" ], filter={ is_system_folder=true, system_folder_key=arguments.id } )
		var folderId       = existingRecord.id ?: "";

		if ( !Len( Trim( folderId ) ) ) {
			var data = duplicate( arguments.settings );

			data.label             = data.label ?: ListLast( arguments.id, "." );
			data.is_system_folder  = true;
			data.system_folder_key = arguments.id;
			data.parent_folder     = arguments.parentId;

			folderId = dao.insertData( data );
		}

		var children = arguments.settings.children ?: {};
		for( var childId in children ){
			_setupConfiguredSystemFolder( ListAppend( arguments.id, childId, "." ), arguments.settings.children[ childId ], folderId );
		}
	}

	private binary function _applyAssetTransformation( required binary assetBinary, required string transformationMethod, required struct transformationArgs ) {
		var args        = Duplicate( arguments.transformationArgs );

		// todo, sanity check the input

		args.asset = arguments.assetBinary;
		return _getAssetTransformer()[ arguments.transformationMethod ]( argumentCollection = args );
	}

	private array function _getPreconfiguredDerivativeTransformations( required string derivativeName ) {
		var configured = _getConfiguredDerivatives();

		if ( StructKeyExists( configured, arguments.derivativeName ) ) {
			return configured[ arguments.derivativeName ].transformations ?: [];
		}

		throw(
			  type    = "AssetManagerService.missingDerivativeConfiguration"
			, message = "No configured asset transformations were found for an asset derivative with name, [#arguments.derivativeName#]"
		);
	}

	private void function _setupConfiguredFileTypesAndGroups( required struct typesByGroup ) {
		var types  = {};
		var groups = {};

		for( var groupName in typesByGroup ){
			if ( IsStruct( typesByGroup[ groupName ] ) ) {
				groups[ groupName ] = StructKeyArray( typesByGroup[ groupName ] );
				for( var typeName in typesByGroup[ groupName ] ) {
					var type = typesByGroup[ groupName ][ typeName ];
					types[ typeName ] = {
						  typeName          = typeName
						, groupName         = groupName
						, extension         = type.extension ?: typeName
						, mimetype          = type.mimetype  ?: ""
						, serveAsAttachment = IsBoolean( type.serveAsAttachment ?: "" ) && type.serveAsAttachment
					};
				}
			}
		}

		_setGroups( groups );
		_setTypes( types );
	}

	private void function _saveAssetMetaData( required string assetId, required struct metaData, string versionId="" ) {
		var dao = _getAssetMetaDao();

		dao.deleteData( filter={ asset=assetId } );
		for( var key in arguments.metaData ) {
			dao.insertData( {
				  asset         = arguments.assetId
				, asset_version = arguments.versionId
				, key           = key
				, value         = arguments.metaData[ key ]
			} );
		}
	}

	private boolean function _autoExtractDocumentMeta() {
		var setting = _getSystemConfigurationService().getSetting( "asset-manager", "retrieve_metadata" );

		return IsBoolean( setting ) && setting;
	}

	private struct function _getExcludeHiddenFilter() {
		return { filter="hidden is null or hidden = 0" }
	}

	private numeric function _getNextAssetVersionNumber( required string assetId ) {
		_setupFirstVersionForAssetIfNoActiveVersion( arguments.assetId );

		var latestVersion = _getAssetVersionDao().selectData(
			  filter = { asset = arguments.assetId }
			, selectFields = [ "Max( version_number ) as version_number" ]
		);

		return Val( latestVersion.version_number ) + 1;
	}

	private void function _setupFirstVersionForAssetIfNoActiveVersion( required string assetId ) {
		var asset = getAsset( id=arguments.assetId, throwOnMissing=true, selectFields=[
			  "storage_path"
			, "size"
			, "asset_type"
			, "active_version"
			, "raw_text_content"
			, "created_by"
			, "updated_by"
		] );

		if ( !Len( Trim( asset.active_version ) ) ) {
			var versionId = _getAssetVersionDao().insertData( {
				  asset            = arguments.assetId
				, version_number   = 1
				, storage_path     = asset.storage_path
				, size             = asset.size
				, asset_type       = asset.asset_type
				, raw_text_content = asset.raw_text_content
				, created_by       = asset.created_by
				, updated_by       = asset.updated_by
			} );

			_getAssetDao().updateData( id=arguments.assetId, data={ active_version=versionId } );
		}
	}

// GETTERS AND SETTERS
	private any function _getStorageProvider() {
		return _storageProvider;
	}
	private void function _setStorageProvider( required any storageProvider ) {
		_storageProvider = arguments.storageProvider;
	}

	private any function _getTemporaryStorageProvider() {
		return _temporaryStorageProvider;
	}
	private void function _setTemporaryStorageProvider( required any temporaryStorageProvider ) {
		_temporaryStorageProvider = arguments.temporaryStorageProvider;
	}

	private any function _getAssetTransformer() {
		return _assetTransformer;
	}
	private void function _setAssetTransformer( required any assetTransformer ) {
		_assetTransformer = arguments.assetTransformer;
	}

	private struct function _getConfiguredDerivatives() {
		return _configuredDerivatives;
	}
	private void function _setConfiguredDerivatives( required struct configuredDerivatives ) {
		_configuredDerivatives = arguments.configuredDerivatives;
	}

	public string function getRootFolderId() {
		return _rootFolderId;
	}
	private void function _setRootFolderId( required string rootFolderId ) {
		_rootFolderId = arguments.rootFolderId;
	}

	private string function _getTrashFolderId() {
		return _trashFolderId;
	}
	private void function _setTrashFolderId( required string trashFolderId ) {
		_trashFolderId = arguments.trashFolderId;
	}

	private any function _getGroups() {
		return _groups;
	}
	private void function _setGroups( required any groups ) {
		_groups = arguments.groups;
	}

	private struct function _getTypes() {
		return _types;
	}
	private void function _setTypes( required struct types ) {
		_types = arguments.types;
	}

	private any function _getSystemConfigurationService() {
		return _systemConfigurationService;
	}
	private void function _setSystemConfigurationService( required any systemConfigurationService ) {
		_systemConfigurationService = arguments.systemConfigurationService;
	}

	private any function _getAssetDao() {
		return _assetDao;
	}
	private void function _setAssetDao( required any assetDao ) {
		_assetDao = arguments.assetDao;
	}

	private any function _getAssetVersionDao() {
		return _assetVersionDao;
	}
	private void function _setAssetVersionDao( required any assetVersionDao ) {
		_assetVersionDao = arguments.assetVersionDao;
	}

	private any function _getFolderDao() {
		return _folderDao;
	}
	private void function _setFolderDao( required any folderDao ) {
		_folderDao = arguments.folderDao;
	}

	private any function _getDerivativeDao() {
		return _derivativeDao;
	}
	private void function _setDerivativeDao( required any derivativeDao ) {
		_derivativeDao = arguments.derivativeDao;
	}

	private any function _getAssetMetaDao() {
		return _assetMetaDao;
	}
	private void function _setAssetMetaDao( required any assetMetaDao ) {
		_assetMetaDao = arguments.assetMetaDao;
	}

	private any function _getTikaWrapper() {
		return _tikaWrapper;
	}
	private void function _setTikaWrapper( required any tikaWrapper ) {
		_tikaWrapper = arguments.tikaWrapper;
	}
}