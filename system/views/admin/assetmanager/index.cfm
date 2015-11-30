<cfscript>
	folder             = rc.folder ?: "";
	folderTitle        = prc.folder.label ?: translateResource( "cms:assetmanager.root.folder" );
	isSystemFolder     = IsTrue( prc.folder.is_system_folder ?: "" );
	folderTree         = prc.folderTree ?: [];
	trashFolderId      = prc.trashFolderId ?: "";
	trashCount         = Val( prc.trashCount ?: "" );
	isTrashFolder      = folder == trashFolderId;
	canManageLocations = hasCmsPermission( "assetmanager.storagelocations.manage" );

	prc.pageIcon     = "picture-o";
	prc.pageTitle    = translateResource( "cms:assetManager" );
	prc.pageSubtitle = folderTitle;


</cfscript>

<cfoutput>

	<div class="info-bar">#renderViewlet( event='admin.assetmanager.searchBox' )#</div>

	<div class="top-right-button-group title-and-actions-container clearfix">
		<cfif canManageLocations>
			<div class="pull-right">
				<a class="inline" href="#event.buildAdminLink( linkTo="assetmanager.managelocations" )#">
					<button class="btn btn-default btn-sm">
						<i class="fa fa-cogs"></i>
						#translateResource( "cms:assetmanager.manage.locations.button" )#
					</button>
				</a>
			</div>
		</cfif>
		<cfif !isTrashFolder>
			#renderView( view="admin/assetmanager/_folderTitleAndActions", args={ folderId=folder, folderTitle=folderTitle, isSystemFolder=isSystemFolder } )#
		</cfif>
	</div>
	<div id="browse" class="row">
		<div class="col-sm-5 col-md-4 col-lg-4">
			<div class="navigation-tree-container">
				<div class="preside-tree-nav tree tree-unselectable" data-nav-list="1" data-nav-list-child-selector=".tree-folder-header,.tree-item">
					<cfloop array="#folderTree#" index="node">
						#renderView( view="/admin/assetmanager/_treeFolderNode", args=node )#
					</cfloop>

					<div class="tree-node tree-item<cfif isTrashFolder> selected</cfif>" data-folder-id="#trashFolderId#">
						<div class="tree-item-name node-name">
							<i class="fa fa-fw fa-trash tree-node-icon red"></i>
							<span class="folder-name">#translateResource( 'cms:assetmanager.trash.folder.name' )# (#trashCount#)</span>
						</div>
					</div>
				</div>
			</div>
		</div>
		<div class="col-sm-7 col-md-8 col-lg-8">
			#renderView( "/admin/assetmanager/listingtable" )#
		</div>
	</div>

	#renderView( '/admin/assetmanager/_moveAssetsForm' )#
</cfoutput>

