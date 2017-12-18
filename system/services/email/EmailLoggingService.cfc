/**
 * Service that provides logic for logging email sends and updates to email delivery status
 *
 * @autodoc        true
 * @singleton      true
 * @presideService true
 */
component {

// CONSTRUCTOR
	/**
	 * @recipientTypeService.inject emailRecipientTypeService
	 * @emailTemplateService.inject emailTemplateService
	 * @emailSettings.inject        coldbox:setting:email
	 *
	 */
	public any function init( required any recipientTypeService, required any emailTemplateService, required any emailSettings ) {
		_setRecipientTypeService( arguments.recipientTypeService );
		_setEmailTemplateService( arguments.emailTemplateService );
		_setEmailSettings( arguments.emailSettings );

		return this;
	}

// PUBLIC API METHODS
	/**
	 * Creates an email log entry and returns its ID (useful for future
	 * status updates to email delivery)
	 *
	 * @autodoc            true
	 * @template.hint      ID of the email template that is being sent
	 * @recipientType.hint ID of the recipient type configured for the template
	 * @recipient.hint     email address of the recipient
	 * @sender.hint        email address of the sender
	 * @subject.hint       Subject line of the email
	 * @sendArgs.hint      Structure of args that were original sent to the email send() method
	 */
	public string function createEmailLog(
		  required string template
		, required string recipientType
		, required string recipientId
		, required string recipient
		, required string sender
		, required string subject
		,          string resendOf = ""
		,          struct sendArgs = {}
	) {
		var data = {
			  email_template = arguments.template
			, recipient      = arguments.recipient
			, sender         = arguments.sender
			, subject        = arguments.subject
			, resend_of      = arguments.resendOf
			, send_args      = SerializeJson( arguments.sendArgs )
		};

		if ( Len( Trim( arguments.recipientType ) ) ) {
			data.append( _getAdditionalDataForRecipientType( arguments.recipientType, arguments.recipientId, arguments.sendArgs ) );
		}

		return $getPresideObject( "email_template_send_log" ).insertData( data );
	}

	/**
	 * Saves the email content of a sent email, to be used to view exact content
	 * sent, and for resending the original email
	 *
	 * @autodoc            true
	 * @id.hint            ID of the email template log record
	 * @htmlBody.hint      HTML content of the email
	 * @textBody.hint      Plain-text content of the email
	 */
	public void function logEmailContent(
		  required string id
		, required string htmlBody
		, required string textBody
	) {
		var contentExpiry = _getEmailSettings().defaultContentExpiry;
		var expires       = now() + contentExpiry;
		var contentId     = $getPresideObject( "email_template_send_log_content" ).insertData( {
			  html_body = arguments.htmlBody
			, text_body = arguments.textBody
			, expires   = expires
		} );

		$getPresideObject( "email_template_send_log" ).updateData( id=arguments.id, data={
			content = contentId
		} );
	}

	/**
	 * Marks the given email as sent
	 *
	 * @autodoc true
	 * @id.hint ID of the email to mark as sent
	 *
	 */
	public void function markAsSent( required string id ) {
		$getPresideObject( "email_template_send_log" ).updateData( id=arguments.id, data={
			  sent      = true
			, sent_date = _getNow()
		} );
	}

	/**
	 * Marks the given email as failed
	 *
	 * @autodoc     true
	 * @id.hint     ID of the email to mark as failed
	 * @reason.hint Failure reason to record
	 * @code.hint   Failure code to record
	 *
	 */
	public void function markAsFailed( required string id, required string reason, string code="" ) {
		$getPresideObject( "email_template_send_log" ).updateData(
			  filter       = "id = :id and ( failed is null or failed = :failed ) and ( opened is null or opened = :opened )"
			, filterParams = { id=arguments.id, failed=false, opened=false }
			, data={
				  failed        = true
				, failed_date   = _getNow()
				, failed_reason = arguments.reason
				, failed_code   = ( Len( Trim( arguments.code ) ) ? Val( arguments.code ) : "" )
			  }
		);
	}


	/**
	 * Marks the given email as 'marked as spam'
	 *
	 * @autodoc     true
	 * @id.hint     ID of the email to mark as marked as spam
	 *
	 */
	public void function markAsMarkedAsSpam( required string id ) {
		$getPresideObject( "email_template_send_log" ).updateData(
			  filter       = "id = :id and ( marked_as_spam is null or marked_as_spam = :marked_as_spam )"
			, filterParams = { id=arguments.id, marked_as_spam=false }
			, data={
				  marked_as_spam      = true
				, marked_as_spam_date = _getNow()
			  }
		);
	}

	/**
	 * Marks the given email as 'unsubscribed'
	 *
	 * @autodoc     true
	 * @id.hint     ID of the email to mark as unsubsribed
	 *
	 */
	public void function markAsUnsubscribed( required string id ) {
		$getPresideObject( "email_template_send_log" ).updateData(
			  filter       = "id = :id and ( unsubscribed is null or unsubscribed = :unsubscribed )"
			, filterParams = { id=arguments.id, unsubscribed=false }
			, data={
				  unsubscribed      = true
				, unsubscribed_date = _getNow()
			  }
		);
	}

	/**
	 * Marks the given email as hard bounced (cannot deliver due to address unkown)
	 *
	 * @autodoc     true
	 * @id.hint     ID of the email to mark as failed
	 * @reason.hint Failure reason to record
	 * @code.hint   Failure code to record
	 *
	 */
	public void function markAsHardBounced( required string id, required string reason, string code="" ) {
		var updated = $getPresideObject( "email_template_send_log" ).updateData(
			  filter       = "id = :id and ( hard_bounced is null or hard_bounced = :hard_bounced ) and ( opened is null or opened = :opened )"
			, filterParams = { id=arguments.id, hard_bounced=false, opened=false }
			, data={
				  hard_bounced      = true
				, hard_bounced_date = _getNow()
			  }
		);

		if ( updated ) {
			markAsFailed(
				  id     = arguments.id
				, reason = arguments.reason
				, code   = arguments.code
			);
		}
	}

	/**
	 * Marks the given email as delivered
	 *
	 * @autodoc       true
	 * @id.hint       ID of the email to mark as delivered
	 * @softMark.hint Used when some other action has occurred that indicates that the message was therefore delivered. i.e. we may not know *when* but we do now know that it *was* delivered.
	 */
	public void function markAsDelivered( required string id, boolean softMark=false ) {
		var data = {
			  delivered         = true
			, hard_bounced      = false
			, hard_bounced_date = ""
			, failed            = false
			, failed_date       = ""
			, failed_reason     = ""
			, failed_code       = ""
		};

		if ( !arguments.softMark ) {
			data.delivered_date = _getNow();
		}

		$getPresideObject( "email_template_send_log" ).updateData(
			  filter       = "id = :id and ( delivered is null or delivered = :delivered )"
			, filterParams = { id=arguments.id, delivered=false }
			, data         = data
		);
	}

	/**
	 * Marks the given email as opened
	 *
	 * @autodoc       true
	 * @id.hint       ID of the email to mark as opened
	 * @softMark.hint Used when some other action has occurred that indicates that the message was therefore opened. i.e. we may not know *when* but we do now know that it *was* opened.
	 *
	 */
	public void function markAsOpened( required string id, boolean softMark=false ) {
		var data = { opened = true };

		if ( !arguments.softMark ) {
			data.opened_date = _getNow();
		}

		$getPresideObject( "email_template_send_log" ).updateData(
			  filter       = "id = :id and ( opened is null or opened = :opened )"
			, filterParams = { id=arguments.id, opened=false }
			, data         = data
		);

		markAsDelivered( arguments.id, true );

		if ( !arguments.softMark ) {
			recordActivity( messageId=arguments.id, activity="open" );
		}
	}

	/**
	 * Records a link click for an email
	 *
	 */
	public void function recordClick( required string id, required string link ) {
		var dao     = $getPresideObject( "email_template_send_log");

		transaction {
			var current = dao.selectData( id=arguments.id );

			if ( current.recordCount ) {
				dao.updateData( id=arguments.id, data={ click_count=Val( current.click_count )+1 } );

				recordActivity(
					  messageId = arguments.id
					, activity  = "click"
					, extraData = { link=arguments.link }
				);

				markAsOpened( id=id, softMark=true );
			}
		}
	}

	/**
	 * Resends an email. A duplicate of the original content is sent
	 *
	 */
	public void function resendOriginalEmail( required string id ) {
		var dao                    = $getPresideObject( "email_template_send_log");
		var message                = dao.selectData(
			  id           = arguments.id
			, selectFields = [
				  "email_template_send_log.*"
				, "content.html_body as html_body"
				, "content.text_body as text_body"
			  ]
		);
		var template               = _getEmailTemplateService().getTemplate( message.email_template );
		var recipientIdLogProperty = _getRecipientTypeService().getRecipientIdLogPropertyForRecipientType( template.recipient_type );
		var sendArgs               = deserializeJson( message.send_args );

		var resentMessageId        = $sendEmail(
		      template              = message.email_template
		    , recipientId           = message[ recipientIdLogProperty ]
		    , to                    = [ message.recipient ]
		    , from                  = message.sender
		    , subject               = message.subject
		    , htmlBody              = message.html_body
		    , textBody              = message.text_body
		    , args                  = sendArgs
		    , resendOf              = message.id
		    , returnLogId           = true
		    , overwriteTemplateArgs = true
		);

		recordActivity(
			  messageId = arguments.id
			, activity  = "resend"
			, userAgent = ""
			, extraData = { resentMessageId=resentMessageId, resendType="original" }
		);

	}

	/**
	 * Resends an email. Email is regenerated using the original sendArgs
	 *
	 */
	public void function rebuildAndResendEmail( required string id ) {
		var dao                    = $getPresideObject( "email_template_send_log");
		var message                = dao.selectData( id=arguments.id );
		var template               = _getEmailTemplateService().getTemplate( message.email_template );
		var recipientIdLogProperty = _getRecipientTypeService().getRecipientIdLogPropertyForRecipientType( template.recipient_type );
		var originalArgs           = deserializeJson( message.send_args );
		var sendArgs               = _getEmailTemplateService().rebuildArgsForResend( template=message.email_template, logId=id, originalArgs=originalArgs );
		var resentMessageId        = $sendEmail(
		      template    = message.email_template
		    , recipientId = message[ recipientIdLogProperty ]
		    , args        = sendArgs
		    , resendOf    = message.id
		    , returnLogId = true
		);

		recordActivity(
			  messageId = arguments.id
			, activity  = "resend"
			, userAgent = ""
			, extraData = { resentMessageId=resentMessageId, resendType="rebuild" }
		);

	}

	/**
	 * Resends an email. Email is regenerated using the original sendArgs
	 *
	 */
	public boolean function deleteExpiredContent( any logger ) {
		var canLog   = arguments.keyExists( "logger" );
		var canInfo  = canLog && logger.canInfo();
		var canError = canLog && logger.canError();
		var dao      = $getPresideObject( "email_template_send_log_content");

		if ( canInfo ) { logger.info( "Deleting expired email content from logs..." ); }

		var deleted  = dao.deleteData(
			  filter       = "expires <= :expires"
			, filterParams = { expires=now() }
		);

		if ( canInfo ) { logger.info( "Content of [#deleted#] emails deleted." ); }

		return true;
	}

	/**
	 * Inserts a tracking pixel into the given HTML email
	 * content (based on the given message ID). Returns
	 * the HTML with the inserted tracking pixel
	 *
	 * @autodoc          true
	 * @messageId.hint   ID of the message (log id)
	 * @messageHtml.hint HTML content of the message
	 */
	public string function insertTrackingPixel(
		  required string messageId
		, required string messageHtml
	) {
		var trackingUrl   = $getRequestContext().buildLink( linkto="email.tracking.open", queryString="mid=" & arguments.messageId );
		var trackingPixel = "<img src=""#trackingUrl#"" width=""1"" height=""1"" style=""width:1px;height:1px"" />";

		if ( messageHtml.findNoCase( "</body>" ) ) {
			return messageHtml.replaceNoCase( "</body>", trackingPixel & "</body>" );
		}

		return messageHtml & trackingPixel;
	}

	/**
	 * converts links in html email to tracking links,
	 * Returns the HTML with the inserted tracking links.
	 *
	 * @autodoc          true
	 * @messageId.hint   ID of the message (log id)
	 * @messageHtml.hint HTML content of the message
	 */
	public string function insertClickTrackingLinks(
		  required string messageId
		, required string messageHtml
	) {
		var converted      = arguments.messageHtml;
		var linkRegex      = 'href="(.*?)"';
		var linkMatches    = converted.reMatchNoCase( linkRegex );
		var baseTrackinUrl = $getRequestContext().buildLink( linkto="email.tracking.click", queryString="mid=#arguments.messageId#&link=" );

		for( var match in linkMatches ) {
			var link = match.reReplaceNoCase( linkRegex , "\1" );

			converted = converted.replace( match, 'href="#baseTrackinUrl##ToBase64( link )#"', "all" );
		}

		return converted;
	}

	/**
	 * Records an activity performed against an specific sent email.
	 * e.g. opened, clicked link, etc.
	 *
	 * @autodoc true
	 * @messageId.hint ID of the message (send log) to record against
	 * @activity.hint  The activity type performed (see system ENUM, `emailActivityType`)
	 * @extraData.hint Structure of additional data that may be useful in email send log viewer (e.g. URL of clicked link)
	 *
	 */
	public void function recordActivity(
		  required string messageId
		, required string activity
		,          struct extraData = {}
		,          string userIp    = cgi.remote_addr
		,          string userAgent = cgi.http_user_agent
	) {
		$getPresideObject( "email_template_send_log_activity" ).insertData({
			  message       = arguments.messageId
			, activity_type = arguments.activity
			, user_ip       = arguments.userIp
			, user_agent    = arguments.userAgent
			, extra_data    = SerializeJson( arguments.extraData )
		});
	}

	/**
	 * Returns a struct of the log (by given id)
	 *
	 * @autodoc
	 * @id.hint ID of the log record
	 */
	public struct function getLog( required string id ) {
		var logRecord = $getPresideObject( "email_template_send_log" ).selectData( id=arguments.id, selectFields=[
			  "email_template_send_log.id"
			, "email_template_send_log.recipient"
			, "email_template_send_log.sender"
			, "email_template_send_log.subject"
			, "email_template_send_log.sent"
			, "email_template_send_log.failed"
			, "email_template_send_log.delivered"
			, "email_template_send_log.opened"
			, "email_template_send_log.marked_as_spam"
			, "email_template_send_log.unsubscribed"
			, "email_template_send_log.sent_date"
			, "email_template_send_log.failed_date"
			, "email_template_send_log.failed_reason"
			, "email_template_send_log.delivered_date"
			, "email_template_send_log.opened_date"
			, "email_template_send_log.marked_as_spam_date"
			, "email_template_send_log.unsubscribed_date"
			, "email_template_send_log.click_count"
			, "email_template_send_log.email_template"
			, "email_template_send_log.datecreated"
			, "email_template_send_log.resend_of"
			, "email_template.name"
			, "email_template.recipient_type"
			, "content.html_body"
			, "content.text_body"
		] );

		for( var l in logRecord ) {
			return l;
		}

		return {};
	}

	/**
	 * Returns a query of an individual log's activity
	 *
	 * @autodoc
	 * @id.hint  ID of the log record
	 */
	public query function getActivity( required string id ) {
		return $getPresideObject( "email_template_send_log_activity" ).selectData(
			  filter  = { message = arguments.id }
			, orderBy = "datecreated"
		);
	}

// PRIVATE HELPERS
	private struct function _getAdditionalDataForRecipientType( required string recipientType, required string recipientId, required struct sendArgs ) {
		var additional           = {};
		var recipientTypeService = _getRecipientTypeService();

		if ( recipientType.len() ) {
			var fkColumn            = recipientTypeService.getRecipientIdLogPropertyForRecipientType( recipientType );
			var additionalSelectors = recipientTypeService.getRecipientAdditionalLogProperties( recipientType );

			if ( fkColumn.len() ) {
				additional[ fkColumn ] = arguments.recipientId
			}
			if ( additionalSelectors.count() ) {
				var fields = [];
				for( var additionalSelector in additionalSelectors ) {
					fields.append( "#additionalSelectors[ additionalSelector ]# as #additionalSelector#" );
				}
				var record = $getPresideObject( recipientTypeService.getFilterObjectForRecipientType( arguments.recipientType ) ).selectData(
					  id           = arguments.recipientId
					, selectFields = fields
					, autoGroupBy  = true
				);
				for( var r in record ) {
					additional.append( r );
				}
			}
		}

		return additional;
	}

	private date function _getNow() {
		return Now(); // abstracting this makes testing easier
	}

// GETTERS AND SETTERS
	private any function _getRecipientTypeService() {
		return _recipientTypeService;
	}
	private void function _setRecipientTypeService( required any recipientTypeService ) {
		_recipientTypeService = arguments.recipientTypeService;
	}

	private any function _getEmailTemplateService() {
		return _emailTemplateService;
	}
	private void function _setEmailTemplateService( required any emailTemplateService ) {
		_emailTemplateService = arguments.emailTemplateService;
	}

	private any function _getEmailSettings() {
		return _emailSettings;
	}
	private void function _setEmailSettings( required any emailSettings ) {
		_emailSettings = arguments.emailSettings;
	}

}