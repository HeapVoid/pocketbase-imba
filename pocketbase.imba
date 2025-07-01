import PocketBase from 'pocketbase'

export class Pocketbase
	pb
	onerror
	onauth
	options = {
		otp: 6
	}
	
	def constructor url\string
		pb = new PocketBase(url)
		auth.refresh(false)

	# ------------------------------------
	# Database methods
	# ------------------------------------
	def create collection\string, record\object
		try
			return await pb.collection(collection).create(record)
		catch error
			onerror('internal_db_error', error) if onerror isa Function
			return false
	
	def view collection\string, filter\string, query = {}
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

	def list collection\string, query = {}
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
			
	def update collection\string, id\string, patch\object
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
			onconnect: do(callback\Function)
				return if !(callback isa Function)
				pb.realtime.subscribe 'PB_CONNECT', do(event) callback(event)
			ondisconnect: do(callback\Function)
				return if !(callback isa Function)
				pb.realtime.onDisconnect = do(event) callback(event)
				
			subscribe: do(collection\string, record\string, callback\Function, oninitfail\Function = undefined, retries = 0)
				try
					await pb.collection(collection).subscribe(record, do(e) callback(e.record, e.action))	
				catch error
					oninitfail(retries,error) if oninitfail isa Function
					setTimeout(&, 1000) do realtime.subscribe(collection, record, callback, oninitfail, retries + 1)
			
			unsubscribe: do(collection\string, record = undefined)
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
			verify: do(email\string) 
				return new RegExp(/^[^\s@]+@[^\s@]+\.[^\s@]+$/).test(email)
			otp: do(email\string)
				if !auth.verify(email)
					onerror('code_send_error', undefined) if onerror isa Function
					return undefined
				try
					return await pb.collection('users').requestOTP(email)
				catch error
					onerror('code_send_error', error) if onerror isa Function
					return undefined
			
			login: do(otp, code)
				if !otp..otpId or !code or code.length != options.otp
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
			