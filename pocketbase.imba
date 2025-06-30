import PocketBase from 'pocketbase'

export class Pocketbase
	pb
	onerror
	onauth
	
	def constructor url
		pb = new PocketBase(url)
		auth.refresh(false)

	# ------------------------------------
	# Database methods
	# ------------------------------------
	def create collection, record
		try
			return await pb.collection(collection).create(record)
		catch error
			onerror('internal_db_error', error) if onerror isa Function
			return false
	
	def view collection, filter, query = {}
		try
			# id is passed as a filter
			if !filter.includes(' ')
				return await pb.collection(collection).getOne(filter, query)
			# get a first item for a passed filter
			else
				return await pb.collection(collection).getFirstListItem(filter, query)
		catch error
			onerror('internal_db_error', error) if onerror isa Function
			return false

	def list collection, query = {}
		query.skipTotal = true if !Object.keys(query).includes('skipTotal')
		try
			if query.limit
				const limit = query.limit
				delete query.limit
				return await pb.collection(collection).getList(1, limit, query)
			elif query.page
				const page = query.page
				const size = query.size || 20
				delete query.page
				delete query.size
				return await pb.collection(collection).getList(page, size, query)
			else
				return await pb.collection(collection).getFullList(query)
		catch error
			onerror('internal_db_error', error) if onerror isa Function
			return false
			
	def update collection, id, patch
		try
			return await pb.collection(collection).update(id, patch)
		catch error
			onerror('internal_db_error', error) if onerror isa Function
			return false

	# ------------------------------------
	# Realtime methods
	# ------------------------------------
	get realtime
		return
			onconnection: do(callback)
				return if !(callback isa Function)
				pb.realtime.onDisconnect = do(event) callback('disconnect', event)
				pb.realtime.subscribe 'PB_CONNECT', do(event) callback('connect', event)

			subscribe: do(collection, record, callback)
				pb.collection(collection).subscribe(record, do(e) callback(e.action, e.record))	
			
			unsubscribe: do(collection, record = undefined)
				if record != undefined
					pb.collection(collection).unsubscribe(record)
				else
					pb.collection(collection).unsubscribe!
		
	# ------------------------------------
	# Authentication methods
	# ------------------------------------			
	get user
		pb.authStore.model
	
	get auth
		return 
			verify: do(email) 
				return new RegExp(/^[^\s@]+@[^\s@]+\.[^\s@]+$/).test(email)
			otp: do(email)
				if !auth.verify(email)
					onerror('code_send_error', undefined) if onerror isa Function
					return undefined
				try
					return await pb.collection('users').requestOTP(email)
				catch error
					onerror('code_send_error', error) if onerror isa Function
					return undefined
			
			login: do(otp, code)
				if !otp..otpId or !code or code.length != 6
					onerror('code_wrong') if onerror isa Function
					return undefined
				try
					await pb.collection('users').authWithOTP(otp..otpId, code)
					onauth! if onauth isa Function
					return true
				catch error
					onerror('code_wrong', error) if onerror isa Function
					return undefined
			
			logout: do(silent = false)
				await pb.authStore.clear!
				onauth! if onauth isa Function and !silent
				
			refresh: do(silent = true)
				if !user
					onauth! if onauth isa Function and !silent
					return
				if user and !pb.authStore.isValid
					auth.logout(silent)
					return 
				try
					await pb.collection("users").authRefresh!
					onauth! if onauth isa Function and silent
				catch error
					onerror('internal_db_error', error) if onerror isa Function
			