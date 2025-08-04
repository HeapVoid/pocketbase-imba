import PocketBase from 'pocketbase'

export const timeout = do(ms) return new Promise(do(resolve) setTimeout(resolve, ms))

export class Pocketbase
	pb
	onerror
	onauth
	oninit
	options = {
		otp: 6
	}
	silent = false
		
	def constructor url\string
		pb = new PocketBase(url)
		auth.refresh!

	def notify code, details = undefined
		return if silent
		if onerror isa Function and !silent
			onerror(code, details)
		else
			console.error "Pocketbase error:", code, details

	# ------------------------------------
	# Database methods
	# ------------------------------------
	def create collection\string, record\object, ecode = 'pocketbase-error'
		try
			return await pb.collection(collection).create(record)
		catch error
			notify(ecode, error)
			return false
	
	def view collection\string, filter\string, query = {}, ecode = 'pocketbase-error'
		try
			query.skipTotal = true if !Object.keys(query).includes('skipTotal')
			# get a first item for a passed filter
			if filter.includes(' ')
				return await pb.collection(collection).getFirstListItem(filter, query)
			# get an item by id which is passed as a filter
			else
				return await pb.collection(collection).getOne(filter, query)
		catch error
			notify(ecode, error)
			return false

	def list collection\string, query = {}, ecode = 'pocketbase-error'
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
			notify(ecode, error)
			return false
			
	def update collection\string, id\string, patch\object, ecode = 'pocketbase-error'
		try
			return await pb.collection(collection).update(id, patch)
		catch error
			notify(ecode, error)
			return false

	def post route\string, query\object = {}, ecode = 'pocketbase-error'
		try
			return await pb.send(route, {method: 'POST', body: query})
		catch error
			notify(ecode, error)
			return false

	def get route\string, query\object = {}, ecode = 'pocketbase-error'
		try
			return await pb.send(route, {method: 'GET', query})
		catch error
			notify(ecode, error)
			return false

	# ------------------------------------
	# Realtime methods
	# ------------------------------------
	get realtime
		return
			connect: do(onconnect\Function = undefined, ondisconnect\Function = undefined, retries = 0)
				pb.realtime.unsubscribe 'PB_CONNECT'
				pb.realtime.onDisconnect = undefined
				try
					await pb.realtime.subscribe 'PB_CONNECT', do(event) onconnect(event) if onconnect isa Function
					pb.realtime.onDisconnect = do(event) 
						return if !(ondisconnect isa Function)
						await timeout(10)
						ondisconnect(event)
				catch error
					ondisconnect(error) if ondisconnect isa Function and !retries
					setTimeout(&, 1000) do realtime.connect(onconnect, ondisconnect, retries + 1)
					
			watch: 
				one: do(collection\string, record\string, callback\Function, onfail\Function = undefined)
					try
						await pb.collection(collection).subscribe(record, do(e) callback(e.record, e.action))
					catch error
						onfail(error) if onfail isa Function
				all: do(collection\string, callback\Function, onfail\Function = undefined)
					try
						await pb.collection(collection).subscribe('*', do(e) callback(e.record, e.action))
					catch error
						onfail(error) if onfail isa Function

			subscribe: 
				one: do(collection\string, record\string, callback\Function, oninitfail\Function = undefined, retries = 0)
					try
						const rec = await pb.collection(collection).getOne(record)
						callback(rec, 'initial')
						await pb.collection(collection).subscribe(record, do(e) callback(e.record, e.action))
					catch error
						oninitfail(retries,error) if oninitfail isa Function
						setTimeout(&, 1000) do realtime.subscribe.one(collection, record, callback, oninitfail, retries + 1)
				all: do(collection\string, callback\Function, oninitfail\Function = undefined, retries = 0)
					try
						await pb.collection(collection).subscribe('*', do(e) callback(e.record, e.action))
					catch error
						oninitfail(retries,error) if oninitfail isa Function
						setTimeout(&, 1000) do realtime.subscribe.all(collection, callback, oninitfail, retries + 1)

			unsubscribe: do(collection\string = undefined, record = undefined)
				if record != undefined
					pb.collection(collection).unsubscribe(record)
				elif collection != undefined
					pb.collection(collection).unsubscribe!
				else
					pb.realtime.unsubscribe!
		
	# ------------------------------------
	# Authentication methods
	# ------------------------------------			
	get user
		return pb.authStore.model if pb.authStore.model and pb.authStore.isValid
		pb.authStore.clear! if pb.authStore.model and !pb.authStore.isValid
		return undefined
	
	get auth
		return 
			verify: do(email\string) 
				return new RegExp(/^[^\s@]+@[^\s@]+\.[^\s@]+$/).test(email)
			otp: do(email\string)
				if !auth.verify(email)
					notify('pocketbase-send-error')
					return undefined
				try
					return await pb.collection('users').requestOTP(email)
				catch error
					notify('pocketbase-send-error', error)
					return undefined
			
			login: do(otp, code)
				if !otp..otpId or !code or code.length != options.otp
					notify('pocketbase-code-wrong')
					return undefined
				try
					await pb.collection('users').authWithOTP(otp..otpId, code)
					onauth! if onauth isa Function
					return true
				catch error
					notify('pocketbase-code-wrong', error)
					return undefined
			
			logout: do
				await pb.authStore.clear!
				onauth! if onauth isa Function
				
			refresh: do
				return if !user
				try await pb.collection("users").authRefresh!
			