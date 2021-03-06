function single_integration(tf,S::CL_state,flags=checkpoints,savename="savefile.h5")
    T=collect(0:dt:tf)
    steps=length(T)
    if steps<flags+1
        error("There are more steps ($steps) than flags ($flags) for saving! Check your timestep, final time and number of flags...")
    end
    Tf=T[Int.(round.(range(1,stop=steps,length=flags+1)))]
    Torig = copy(Tf)
    Rvec=zeros(Float64,flags+1,S.cl.NDOFs)
    pvec=zeros(Float64,flags+1,S.cl.NDOFs)
    E0 = energy(S)

    counter=2
    Rvec[1,:].=S.cl.R
    pvec[1,:].=S.cl.p
    dt_ini=dt
    t00=time()
    for i in 2:flags+1
        S,Tf[i],dt_ini=runge_bigstep(S,Tf[i-1],Tf[i],dt_ini)
        Rvec[i,:].=S.cl.R
        pvec[i,:].=S.cl.p
        if high_verbose
            println("Currently at R=$(S.cl.R), p=$(S.cl.p), T=$(Tf[i]), time since last check:")
            t01=time()
            println(t01-t00,5," seconds passed")
            t00=t01
            E=energy(S)
            println("Current energy (compared to initial energy) changed relatively by $(1-E/E0)")
        end
    end

    if sanity_checks
        energy(S)
        health_check(S,E0)
    end

    if IND_SAVES
        CL_FULL_SAVE(Torig,Rvec,pvec,savename,S.prefix)
    end

    return Tf,Rvec,pvec
end

function single_integration(tf,S::MF_state,flags=checkpoints,savename="savefile.h5")
    T=collect(0:dt:tf)
    steps=length(T)
    if steps<flags+1
        error("There are more steps ($steps) than flags ($flags) for saving! Check your timestep, final time and number of flags...")
    end
    Tf=T[Int.(round.(range(1,stop=steps,length=flags+1)))]
    Torig = copy(Tf)
    Rvec=zeros(Float64,flags+1,S.cl.NDOFs)
    pvec=zeros(Float64,flags+1,S.cl.NDOFs)
    tr_sts=length(S.el.C) #number of electronic states that will be tracked over dynamics
    C=zeros(Complex,flags+1,tr_sts)

    E0 = energy(S)

    counter=2
    Rvec[1,:].=S.cl.R
    pvec[1,:].=S.cl.p
    C[1,:].=S.el.C
    t00=time() #uncomment for printing debug mode
    dt_ini=dt
    for i in 2:flags+1
        S,Tf[i],dt_ini=runge_bigstep(S,Tf[i-1],Tf[i],dt_ini)
        Rvec[i,:].=S.cl.R
        pvec[i,:].=S.cl.p
        C[i,:].=S.el.C
        if high_verbose
            println("Currently at R=$(S.cl.R), p=$(S.cl.p), Cnorm=$(sum(abs2.(S.el.C))), T=$(Tf[i]), time since last check:")
            t01=time()
            println(t01-t00,5," seconds passed")
            t00=t01
            E=energy(S)
            println("Current energy (compared to initial energy) changed relatively by $(1-E/E0)")
        end
    end

    if sanity_checks
        energy(S)
        health_check(S,E0)
    end

    if IND_SAVES
        MF_FULL_SAVE(Torig,Rvec,pvec,C,savename,S.prefix)
    end

    return Tf,Rvec,pvec,C
end

function single_integration(tf,S::SH_state,flags=checkpoints,savename="savefile.h5")
    T=collect(0:dt:tf)
    steps=length(T)
    if steps<flags+1
        error("There are more steps ($steps) than flags ($flags) for saving! Check your timestep, final time and number of flags...")
    end
    Tf=T[Int.(round.(range(1,stop=steps,length=flags+1)))]
    Torig = copy(Tf)
    Rvec=zeros(Float64,flags+1,S.cl.NDOFs)
    pvec=zeros(Float64,flags+1,S.cl.NDOFs)
    tr_sts=length(S.el.C) #number of electronic states to track
    C=zeros(Complex,flags+1,tr_sts)
    Ast=zeros(Int,flags+1)

    E0 = energy(S)

    counter=2
    Rvec[1,:].=S.cl.R
    pvec[1,:].=S.cl.p
    C[1,:].=S.el.C
    Ast[1]=S.ast
    dt_ini=dt
    t00=time()
    for i in 2:flags+1
        S,Tf[i],dt_ini=runge_bigstep(S,Tf[i-1],Tf[i],dt_ini)
        Rvec[i,:].=S.cl.R
        pvec[i,:].=S.cl.p
        C[i,:].=S.el.C
        Ast[i]=S.ast
        if high_verbose
            println("Currently at R=$(S.cl.R), p=$(S.cl.p), Cnorm=$(sum(abs2.(S.el.C))), T=$(Tf[i]), ast=$(S.ast) time since last check:")
            t01=time()
            println(t01-t00,5," seconds passed")
            t00=t01
            E=energy(S)
            println("Current energy (compared to initial energy) changed relatively by $(1-E/E0)")
        end
    end

    if sanity_checks
        energy(S)
        health_check(S,E0)
    end

    if IND_SAVES
        SH_FULL_SAVE(Torig,Rvec,pvec,C,Ast,savename,S.prefix)
    end

    return Tf,Rvec,pvec,C,Ast
end


function wigner_CL_integration(tf,R0,p0,mem,prefix,Ntrajs,flags=checkpoints,savename="savefile.h5")
    @everywhere NDOFs=length(R0)
    R_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    P_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    INITIAL=initial_1D_distribution([R0,p0],wigner,Ntrajs)
    S0=[builder_CL_state(INITIAL[1,i],INITIAL[2,i],prefix,0,NDOFs,mem,[],true) for i in 1:Ntrajs]

    T=collect(0:dt:tf)
    steps=length(T)
    TF=SharedArray(T[Int.(round.(range(1,stop=steps,length=flags+1)))])
    REMAINING=SharedArray{Int64}(1)
    REMAINING[1]=Ntrajs

    @sync @distributed for i in 1:Ntrajs
            @time Tf,Rvec,pvec=single_integration(tf,S0[i],flags,savename * prefix * ".$i.h5")
            if length(TF)<length(Tf)
                push!(TF,Tf[end])
            end
            R_VEC[:,:,i].=Rvec
            P_VEC[:,:,i].=pvec
            REMAINING[1]+=-1
            println("$(REMAINING[1]) trajectories remaining")
    end

    println("Finished CL integration, passing to full save...")
    CL_FULL_SAVE(TF,R_VEC,P_VEC,savename,prefix)

    if IND_SAVES
        println("Removing individual saves...")
        for i in 1:Ntrajs
            rm(savename * prefix * ".$i.h5")
        end
    end

    return TF,R_VEC,P_VEC
end

function wigner_MF_integration(tf,R0,p0,C0,mem,prefix,Ntrajs,flags=checkpoints,savename="savefile.h5")
    @everywhere NDOFs=length(R0)
    R_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    P_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    C_VEC=SharedArray{Complex128}(flags+1,nsts,Ntrajs)
    INITIAL=initial_1D_distribution([R0,p0],wigner,Ntrajs)
    S0=[builder_MF_state(INITIAL[1,i],INITIAL[2,i],C0,prefix,0,NDOFs,mem,[],true) for i in 1:Ntrajs]

    T=collect(0:dt:tf)
    steps=length(T)
    TF=SharedArray(T[Int.(round.(range(1,stop=steps,length=flags+1)))])
    REMAINING=SharedArray{Int64}(1)
    REMAINING[1]=Ntrajs

    @sync @distributed for i in 1:Ntrajs
            @time Tf,Rvec,pvec,C=single_integration(tf,S0[i],flags,savename * prefix * ".$i.h5")
            if length(TF)<length(Tf)
                push!(TF,Tf[end])
            end
            R_VEC[:,:,i].=Rvec
            P_VEC[:,:,i].=pvec
            C_VEC[:,:,i].=C
            REMAINING[1]+=-1
            println("$(REMAINING[1]) trajectories remaining")
    end

    println("Finished MF integration, passing to full save...")
    MF_FULL_SAVE(TF,R_VEC,P_VEC,C_VEC,savename,prefix)
    
    if IND_SAVES
        println("Removing individual saves...")
        for i in 1:Ntrajs
            rm(savename * prefix * ".$i.h5")
        end
    end

    return TF,R_VEC,P_VEC,C_VEC
end

function wigner_SH_integration(tf,R0,p0,C0,ast0,mem,prefix,Ntrajs,flags=checkpoints,savename="savefile.h5")
    @everywhere NDOFs=length(R0)
    R_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    P_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    tr_sts=length(C0)
    C_VEC=SharedArray{Complex}(flags+1,tr_sts,Ntrajs)
    AST_VEC=SharedArray{Int64}(flags+1,Ntrajs)
    INITIAL=initial_1D_distribution([R0,p0],wigner,Ntrajs)
    S0=[builder_SH_state(INITIAL[1,i],INITIAL[2,i],C0,ast0,prefix,0,NDOFs,mem,[],true) for i in 1:Ntrajs]

    T=collect(0:dt:tf)
    steps=length(T)
    TF=SharedArray(T[Int.(round.(range(1,stop=steps,length=flags+1)))])
    REMAINING=SharedArray{Int64}(1)
    REMAINING[1]=Ntrajs

    @sync @distributed for i in 1:Ntrajs
            @time Tf,Rvec,pvec,C,Ast=single_integration(tf,S0[i],flags,savename * prefix * ".$i.h5")
            if length(TF)<length(Tf)
                push!(TF,Tf[end])
            end
            R_VEC[:,:,i].=Rvec
            P_VEC[:,:,i].=pvec
            C_VEC[:,:,i].=C
            AST_VEC[:,i].=Ast
            REMAINING[1]+=-1
            println("$(REMAINING[1]) trajectories remaining")
    end

    println("Finished SH integration, passing to full save...")
    SH_FULL_SAVE(TF,R_VEC,P_VEC,C_VEC,AST_VEC,savename,prefix)
    
    if IND_SAVES
        println("Removing individual saves...")
        for i in 1:Ntrajs
            rm(savename * prefix * ".$i.h5")
        end
    end

        return TF,R_VEC,P_VEC,C_VEC,AST_VEC
end

function dist_CL_integration(tf,R0,p0,mem,prefix,Ntrajs,DIST,flags=checkpoints,savename="savefile.h5")
    if DIST==constant_dist
        println("Warning: running many classical trajectories with same initial conditions, one trajectory is enough")
    end
    @everywhere NDOFs=length(R0)
    R_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    P_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    INITIAL=initial_1D_distribution([R0,p0],DIST,Ntrajs)
    S0=[builder_CL_state(INITIAL[1,i],INITIAL[2,i],prefix,0,NDOFs,mem,[],true) for i in 1:Ntrajs]

    T=collect(0:dt:tf)
    steps=length(T)
    TF=SharedArray(T[Int.(round.(range(1,stop=steps,length=flags+1)))])
    REMAINING=SharedArray{Int64}(1)
    REMAINING[1]=Ntrajs

    @sync @distributed for i in 1:Ntrajs
            @time Tf,Rvec,pvec=single_integration(tf,S0[i],flags,savename * prefix * ".$i.h5")
            if length(TF)<length(Tf)
                push!(TF,Tf[end])
            end
            R_VEC[:,:,i].=Rvec
            P_VEC[:,:,i].=pvec
            REMAINING[1]+=-1
            println("$(REMAINING[1]) trajectories remaining")
    end

    println("Finished CL integration, passing to full save...")
    CL_FULL_SAVE(TF,R_VEC,P_VEC,savename,prefix)

    if IND_SAVES
        println("Removing individual saves...")
        for i in 1:Ntrajs
            rm(savename * prefix * ".$i.h5")
        end
    end

        return TF,R_VEC,P_VEC
end

function dist_MF_integration(tf,R0,p0,C0,mem,prefix,Ntrajs,DIST,flags=checkpoints,savename="savefile.h5")
    if DIST==constant_dist
        println("Warning: running many classical trajectories with same initial conditions, one trajectory is enough")
    end
    @everywhere NDOFs=length(R0)
    R_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    P_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    tr_sts=length(C0)
    C_REAL_VEC=SharedArray{Float64}(flags+1,tr_sts,Ntrajs)
    C_IMAG_VEC=SharedArray{Float64}(flags+1,tr_sts,Ntrajs)
    INITIAL=initial_1D_distribution([R0,p0],DIST,Ntrajs)
    S0=[builder_MF_state(INITIAL[1,i],INITIAL[2,i],C0,prefix,0,NDOFs,mem,[],true) for i in 1:Ntrajs]

    T=collect(0:dt:tf)
    steps=length(T)
    TF=SharedArray(T[Int.(round.(range(1,stop=steps,length=flags+1)))])
    REMAINING=SharedArray{Int64}(1)
    REMAINING[1]=Ntrajs

    @sync @distributed for i in 1:Ntrajs
            @time Tf,Rvec,pvec,C=single_integration(tf,S0[i],flags,savename * prefix * ".$i.h5")
            if length(TF)<length(Tf)
                push!(TF,Tf[end])
            end
            R_VEC[:,:,i].=Rvec
            P_VEC[:,:,i].=pvec
            C_REAL_VEC[:,:,i].=Float64.(real.(C))
            C_IMAG_VEC[:,:,i].=Float64.(imag.(C))
            REMAINING[1]+=-1
            println("$(REMAINING[1]) trajectories remaining")
    end

    C_VEC=C_REAL_VEC.+1im*C_IMAG_VEC
    println("Finished MF integration, passing to full save...")
    MF_FULL_SAVE(TF,R_VEC,P_VEC,C_VEC,savename,prefix)

    if IND_SAVES
        println("Removing individual saves...")
        for i in 1:Ntrajs
            rm(savename * prefix * ".$i.h5")
        end
    end

        return TF,R_VEC,P_VEC,C_VEC
end

function dist_SH_integration(tf,R0,p0,C0,ast0,mem,prefix,Ntrajs,DIST,extra=[],flags=checkpoints,savename="savefile.h5")
    @everywhere NDOFs=length(R0)
    R_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    P_VEC=SharedArray{Float64}(flags+1,NDOFs,Ntrajs)
    tr_sts=length(C0)
    C_REAL_VEC=SharedArray{Float64}(flags+1,tr_sts,Ntrajs)
    C_IMAG_VEC=SharedArray{Float64}(flags+1,tr_sts,Ntrajs)
    AST_VEC=SharedArray{Int64}(flags+1,Ntrajs)
    INITIAL=initial_1D_distribution([R0,p0],DIST,Ntrajs)
    S0=[builder_SH_state(INITIAL[1,i],INITIAL[2,i],C0,ast0,prefix,0,NDOFs,mem,extra,true) for i in 1:Ntrajs]

    T=collect(0:dt:tf)
    steps=length(T)
    TF=SharedArray(T[Int.(round.(range(1,stop=steps,length=flags+1)))])
    REMAINING=SharedArray{Int64}(1)
    REMAINING[1]=Ntrajs

    @sync @distributed for i in 1:Ntrajs
            @time Tf,Rvec,pvec,C,Ast=single_integration(tf,S0[i],flags,savename * prefix * ".$i.h5")
            if length(TF)<length(Tf)
                push!(TF,Tf[end])
            end
            R_VEC[:,:,i].=Rvec
            P_VEC[:,:,i].=pvec
            C_REAL_VEC[:,:,i].=Float64.(real.(C))
            C_IMAG_VEC[:,:,i].=Float64.(imag.(C))
            AST_VEC[:,i].=Ast
            REMAINING[1]+=-1
            println("$(REMAINING[1]) trajectories remaining")
    end

    C_VEC=C_REAL_VEC.+1im*C_IMAG_VEC

    println("Finished SH integration, passing to full save...")
    SH_FULL_SAVE(TF,R_VEC,P_VEC,C_VEC,AST_VEC,savename,prefix)

    if IND_SAVES
        println("Removing individual saves...")
        for i in 1:Ntrajs
            rm(savename * prefix * ".$i.h5")
        end
    end

    return TF,R_VEC,P_VEC,C_VEC,AST_VEC
end


########### TRAVEL DISTANCE INTEGRATIONS

function single_distance_integration(R_min,S,tmax=walltime)
    tf=0
    ds=dt
    T=Float64[]
    E0=energy(S)
    if time_print
        sizehint!(T,Int(round(tmax/dt)))
    end
    if length(R_min)==1
        while S.cl.R-R_min<0 && tf<tmax
            tstep,S,ds=runge_step(S,ds,false)
            tf+=tstep
            if time_print
                push!(T,tstep)
            end
        end
    elseif length(R_min)==2
        while S.cl.R-R_min[2]<0 && S.cl.R-R_min[1]>0 && tf<tmax
            tstep,S,ds=runge_step(S,ds,false)
            tf+=tstep
            if time_print
                push!(T,tstep)
            end
        end
    else
        error("R_min is neither a number nor an interval!")
    end

    if tf>=tmax
        println("Warning! Trajectory ended due to walltime, still inside interaction at R=$(S.cl.R) and p=$(S.cl.p)")
    end

    if time_print
        @show maximum(T),minimum(T),mean(T)
    end
    #sanity check subroutine
    if sanity_checks
        health_check(S,E0)
    end

    return tf,S
end


function many_distance_integration(R_min,S::SH_state,Ntrajs,tmax=walltime)
    #this kind of integration will only be useful for surface hopping schemes,
    #since mean-field schemes only need to be integrated once
    S_array=[S for k in 1:Ntrajs]
    T_array=SharedArray{Float64}(Ntrajs)
    R_array=SharedArray{Float64}(Ntrajs,S.cl.NDOFs)
    P_array=SharedArray{Float64}(Ntrajs,S.cl.NDOFs)
    tr_sts=eval(Meta.parse("$(S.prefix)_sts"))
    C_real_array=SharedArray{Float64}(Ntrajs,tr_sts)
    C_imag_array=SharedArray{Float64}(Ntrajs,tr_sts)
    AST_array=SharedArray{Int64}(Ntrajs)
    REMAINING=SharedArray{Int64}(1)
    REMAINING[1]=Ntrajs

    @sync @distributed for i in 1:Ntrajs
        @time T_array[i],S=single_distance_integration(R_min,S_array[i],tmax)
        REMAINING[1]+=-1
        println("$(REMAINING[1]) trajectories remaining")
        R_array[i,:].=S.cl.R
        P_array[i,:].=S.cl.p
        C_real_array[i,:].=real.(S.el.C)
        C_imag_array[i,:].=imag.(S.el.C)
        AST_array[i]=S.ast
    end

    C_array=C_real_array+1im.*C_imag_array
    return T_array,R_array,P_array,C_array,AST_array
end


#########################################################
function full_memory_integration(tf,S::CL_state)
    T=collect(0:dt:tf)
    steps=length(T)
    S_ARRAY=[S for i in 1:steps]

    #t00=time()
    for i in 2:steps
        S_ARRAY[i]=runge_step(S_ARRAY[i-1])
    end

    return T,S_ARRAY
end

function full_memory_integration(tf,S::MF_state)
    T=collect(0:dt:tf)
    steps=length(T)
    S_ARRAY=[S for i in 1:steps]

    #t00=time()
    for i in 2:steps
        S_ARRAY[i]=runge_step(S_ARRAY[i-1])
    end

    return T,S_ARRAY
end

function full_memory_integration(tf,S::SH_state)
    T=collect(0:dt:tf)
    steps=length(T)
    S_ARRAY=[S for i in 1:steps]

    #t00=time()
    for i in 2:steps
        S_ARRAY[i]=runge_step(S_ARRAY[i-1])
        S_ARRAY[i]=hop!(S_ARRAY[i])
    end

    return T,S_ARRAY
end
