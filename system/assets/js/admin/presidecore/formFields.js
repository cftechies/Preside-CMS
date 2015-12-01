( function( $ ){

	$(".object-picker").presideObjectPicker();
	$(".asset-picker").uberAssetSelect();
	$(".image-dimension-picker").imageDimensionPicker();

	$(".auto-slug").each( function(){
		var $this = $(this)
		  , $basedOn = $this.parents("form:first").find("[name='" + $this.data( 'basedOn' ) + "']");

		$basedOn.keyup( function(e){
			var slug = $basedOn.val().replace( /\W/g, "-" ).replace( /-+/g, "-" ).toLowerCase();

			$this.val( slug );
		} );
	});

	$( 'textarea[class*=autosize]' ).autosize( {append: "\n"} );
	$( 'textarea[class*=limited]' ).each(function() {
		var limit = parseInt($(this).attr('data-maxlength')) || 100;
		$(this).inputlimiter({
			"limit": limit,
			remText: '%n character%s remaining...',
			limitText: 'max allowed : %n.'
		});
	});
	$( 'textarea.richeditor' ).not( '.frontend-container' ).each( function(){
		new PresideRichEditor( this );
	} );

	$('.date-picker')
		.datepicker( { autoclose:true } )
		.next().on( "click", function(){
			$(this).prev().focus();
		});

	$('[data-rel=popover]').popover({container:'body'});

	$('.datetimepicker').datetimepicker({
		icons: {
            time: 'fa fa-clock-o',
            date: 'fa fa-calendar',
            up: 'fa fa-chevron-up',
            down: 'fa fa-chevron-down',
            previous: 'fa fa-chevron-left',
            next: 'fa fa-chevron-right',
            today: 'fa fa-screenshot',
            clear: 'fa fa-trash'
        },

        format: 'YYYY-MM-DD HH:mm',

        sideBySide:true
	});


	$('#derivativePicker').change(function(){
		var setWidth     = $('.image-dimensions-picker-width');
		var setHeight    = $('.image-dimensions-picker-height');
		var setDimension = $('#dimensions');
		var key          = $('#derivativePicker_chosen .chosen-hidden-field').val();
		var width        = $(this).find('option[value='+ key +']').attr('data-width');
		var height       = $(this).find('option[value='+ key +']').attr('data-height');

		setWidth.val( width );
		setHeight.val( height );
		setDimension.val( width+'x'+height);

	});

} )( presideJQuery );