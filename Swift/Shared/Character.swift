/*
See LICENSE folder for this sample’s licensing information.

Abstract:
This class manages the main character, including its animations, sounds and direction.
*/

import Foundation
import SceneKit
import simd

// Returns plane / ray intersection distance from ray origin.
func planeIntersect(planeNormal: float3, planeDist: Float, rayOrigin: float3, rayDirection: float3) -> Float {
    return (planeDist - simd_dot(planeNormal, rayOrigin)) / simd_dot(planeNormal, rayDirection)
}

class Character: NSObject {
    
    static private let speedFactor: CGFloat = 2.0
    static private let stepsCount = 10

    static private let initialPosition = float3(0.1, -0.2, 0)
    
    // some constants
    static private let gravity = Float(0.004)
    static private let jumpImpulse = Float(0.1)
    static private let minAltitude = Float(0)
    static private let enableFootStepSound = true
    static private let collisionMargin = Float(0.04)
    static private let modelOffset = float3(0, -collisionMargin, 0)
    static private let collisionMeshBitMask = 8
    
    enum GroundType: Int {
        case grass
        case rock
        case water
        case inTheAir
        case count
    }
    
    // Character handle
    private var characterNode: SCNNode! // top level node
    private var characterOrientation: SCNNode! // the node to rotate to orient the character
    private var model: SCNNode! // the model loaded from the character file
    
    // Physics
    private var characterCollisionShape: SCNPhysicsShape?
    private var collisionShapeOffsetFromModel = float3.zero
    private var downwardAcceleration: Float = 0
    
    // Jump
    private var controllerJump: Bool = false
    private var jumpState: Int = 0
    private var groundNode: SCNNode?
    private var groundNodeLastPosition = float3.zero
    var baseAltitude: Float = 0
    private var targetAltitude: Float = 0
    
    // void playing the step sound too often
    private var lastStepFrame: Int = 0
    private var frameCounter: Int = 0
    
    // Direction
    private var previousUpdateTime: TimeInterval = 0
    private var controllerDirection = float2.zero
    
    // states
    private var attackCount: Int = 0
    private var lastHitTime: TimeInterval = 0
    
    private var shouldResetCharacterPosition = false
    
    // Particle systems
    private var jumpDustParticle: SCNParticleSystem!
    private var fireEmitter: SCNParticleSystem!
    private var smokeEmitter: SCNParticleSystem!
    private var whiteSmokeEmitter: SCNParticleSystem!
    private var spinParticle: SCNParticleSystem!
    private var spinCircleParticle: SCNParticleSystem!

    private var spinParticleAttach: SCNNode!

    private var fireEmitterBirthRate: CGFloat = 0.0
    private var smokeEmitterBirthRate: CGFloat = 0.0
    private var whiteSmokeEmitterBirthRate: CGFloat = 0.0

    // Sound effects
    private var aahSound: SCNAudioSource!
    private var ouchSound: SCNAudioSource!
    private var hitSound: SCNAudioSource!
    private var hitEnemySound: SCNAudioSource!
    private var explodeEnemySound: SCNAudioSource!
    private var catchFireSound: SCNAudioSource!
    private var jumpSound: SCNAudioSource!
    private var attackSound: SCNAudioSource!
    private var steps = [SCNAudioSource](repeating: SCNAudioSource(), count: Character.stepsCount )
    
    private(set) var offsetedMark: SCNNode?
    
    // actions
    var isJump: Bool = false
    var direction = float2()
    var physicsWorld: SCNPhysicsWorld?
    
    // MARK: - Initialization
    init(scene: SCNScene) {
        super.init()

        loadCharacter()
        loadParticles()
        loadSounds()
        loadAnimations()
    }

    private func loadCharacter() {
        /// Load character from external file
        let scene = SCNScene( named: "Art.scnassets/character/max.scn")!
        model = scene.rootNode.childNode( withName: "Max_rootNode", recursively: true)
        
        // 可以動畫的 simdPosition
        model.simdPosition = Character.modelOffset

        /* setup character hierarchy
         character
         |_orientationNode
         |_model
         */
        characterNode = SCNNode()
        characterNode.name = "character"
        characterNode.simdPosition = Character.initialPosition

        characterOrientation = SCNNode()
        characterNode.addChildNode(characterOrientation)
        characterOrientation.addChildNode(model)

        let collider = model.childNode(withName: "collider", recursively: true)!
        
        // 設定碰撞節點的物理特性
        collider.physicsBody?.collisionBitMask = Int(([ .enemy, .trigger, .collectable ] as Bitmask).rawValue)

        // Setup collision shape
        
        // boundingBox -> The minimum and maximum corner points of the object’s bounding box.
        let (min, max) = model.boundingBox  // 可以把物件整個包起來的 bounding 空間
        let collisionCapsuleRadius = CGFloat(max.x - min.x) * CGFloat(0.4)
        let collisionCapsuleHeight = CGFloat(max.y - min.y)
        
        // 做出碰撞範圍的膠囊體
        let collisionGeometry = SCNCapsule(capRadius: collisionCapsuleRadius, height: collisionCapsuleHeight)
        
        // 碰撞外型
        // collisionMargin 目前位置
        characterCollisionShape = SCNPhysicsShape(geometry: collisionGeometry, options:[.collisionMargin: Character.collisionMargin])
        collisionShapeOffsetFromModel = float3(0, Float(collisionCapsuleHeight) * 0.51, 0.0)
    }

    private func loadParticles() {
        var particleScene = SCNScene( named: "Art.scnassets/character/jump_dust.scn")!
        let particleNode = particleScene.rootNode.childNode(withName: "particle", recursively: true)!
        jumpDustParticle = particleNode.particleSystems!.first!

        particleScene = SCNScene( named: "Art.scnassets/particles/burn.scn")!
        let burnParticleNode = particleScene.rootNode.childNode(withName: "particles", recursively: true)!

        let particleEmitter = SCNNode()
        characterOrientation.addChildNode(particleEmitter)

        fireEmitter = burnParticleNode.childNode(withName: "fire", recursively: true)!.particleSystems![0]
        fireEmitterBirthRate = fireEmitter.birthRate
        fireEmitter.birthRate = 0

        smokeEmitter = burnParticleNode.childNode(withName: "smoke", recursively: true)!.particleSystems![0]
        smokeEmitterBirthRate = smokeEmitter.birthRate
        smokeEmitter.birthRate = 0

        whiteSmokeEmitter = burnParticleNode.childNode(withName: "whiteSmoke", recursively: true)!.particleSystems![0]
        whiteSmokeEmitterBirthRate = whiteSmokeEmitter.birthRate
        whiteSmokeEmitter.birthRate = 0

        particleScene = SCNScene(named:"Art.scnassets/particles/particles_spin.scn")!
        spinParticle = (particleScene.rootNode.childNode(withName: "particles_spin", recursively: true)?.particleSystems?.first!)!
        spinCircleParticle = (particleScene.rootNode.childNode(withName: "particles_spin_circle", recursively: true)?.particleSystems?.first!)!

        particleEmitter.position = SCNVector3Make(0, 0.05, 0)
        particleEmitter.addParticleSystem(fireEmitter)
        particleEmitter.addParticleSystem(smokeEmitter)
        particleEmitter.addParticleSystem(whiteSmokeEmitter)

        spinParticleAttach = model.childNode(withName: "particles_spin_circle", recursively: true)
    }

    private func loadSounds() {
        aahSound = SCNAudioSource( named: "audio/aah_extinction.mp3")!
        aahSound.volume = 1.0
        aahSound.isPositional = false
        aahSound.load()

        catchFireSound = SCNAudioSource(named: "audio/panda_catch_fire.mp3")!
        catchFireSound.volume = 5.0
        catchFireSound.isPositional = false
        catchFireSound.load()

        ouchSound = SCNAudioSource(named: "audio/ouch_firehit.mp3")!
        ouchSound.volume = 2.0
        ouchSound.isPositional = false
        ouchSound.load()

        hitSound = SCNAudioSource(named: "audio/hit.mp3")!
        hitSound.volume = 2.0
        hitSound.isPositional = false
        hitSound.load()

        hitEnemySound = SCNAudioSource(named: "audio/Explosion1.m4a")!
        hitEnemySound.volume = 2.0
        hitEnemySound.isPositional = false
        hitEnemySound.load()

        explodeEnemySound = SCNAudioSource(named: "audio/Explosion2.m4a")!
        explodeEnemySound.volume = 2.0
        explodeEnemySound.isPositional = false
        explodeEnemySound.load()

        jumpSound = SCNAudioSource(named: "audio/jump.m4a")!
        jumpSound.volume = 0.2
        jumpSound.isPositional = false
        jumpSound.load()

        attackSound = SCNAudioSource(named: "audio/attack.mp3")!
        attackSound.volume = 1.0
        attackSound.isPositional = false
        attackSound.load()
        
        // 處理腳步聲音
        for i in 0..<Character.stepsCount {
            steps[i] = SCNAudioSource(named: "audio/Step_rock_0\(UInt32(i)).mp3")!
            steps[i].volume = 0.5
            steps[i].isPositional = false
            steps[i].load()
        }
    }

    private func loadAnimations() {
        
        // 從素材檔案身上讀取素材動畫
        let idleAnimation = Character.loadAnimation(fromSceneNamed: "Art.scnassets/character/max_idle.scn")
        model.addAnimationPlayer(idleAnimation, forKey: "idle")
        idleAnimation.play()

        let walkAnimation = Character.loadAnimation(fromSceneNamed: "Art.scnassets/character/max_walk.scn")
        walkAnimation.speed = Character.speedFactor
        walkAnimation.stop()

        if Character.enableFootStepSound {
            walkAnimation.animation.animationEvents = [
                SCNAnimationEvent(keyTime: 0.1, block: { _, _, _ in self.playFootStep() }),
                SCNAnimationEvent(keyTime: 0.6, block: { _, _, _ in self.playFootStep() })
            ]
        }
        model.addAnimationPlayer(walkAnimation, forKey: "walk")

        let jumpAnimation = Character.loadAnimation(fromSceneNamed: "Art.scnassets/character/max_jump.scn")
        jumpAnimation.animation.isRemovedOnCompletion = false
        jumpAnimation.stop()
        jumpAnimation.animation.animationEvents = [SCNAnimationEvent(keyTime: 0, block: { _, _, _ in self.playJumpSound() })]
        model.addAnimationPlayer(jumpAnimation, forKey: "jump")

        let spinAnimation = Character.loadAnimation(fromSceneNamed: "Art.scnassets/character/max_spin.scn")
        spinAnimation.animation.isRemovedOnCompletion = false
        spinAnimation.speed = 1.5
        spinAnimation.stop()
        spinAnimation.animation.animationEvents = [SCNAnimationEvent(keyTime: 0, block: { _, _, _ in self.playAttackSound() })]
        model!.addAnimationPlayer(spinAnimation, forKey: "spin")
    }

    var node: SCNNode! {
        return characterNode
    }
        
    func queueResetCharacterPosition() {
        shouldResetCharacterPosition = true
    }
    
    // MARK: Audio
    
    func playFootStep() {
        if groundNode != nil && isWalking { // We are in the air, no sound to play.
            // Play a random step sound.
            let randSnd: Int = Int(Float(arc4random()) / Float(RAND_MAX) * Float(Character.stepsCount))
            let stepSoundIndex: Int = min(Character.stepsCount - 1, randSnd)
            characterNode.runAction(SCNAction.playAudio( steps[stepSoundIndex], waitForCompletion: false))
        }
    }
    
    func playJumpSound() {
        characterNode!.runAction(SCNAction.playAudio(jumpSound, waitForCompletion: false))
    }
    
    func playAttackSound() {
        characterNode!.runAction(SCNAction.playAudio(attackSound, waitForCompletion: false))
    }
    
    var isBurning: Bool = false {
        didSet {
            if isBurning == oldValue {
                return
            }
            //walk faster when burning
            let oldSpeed = walkSpeed
            walkSpeed = oldSpeed
            
            if isBurning {
                model.runAction(SCNAction.sequence([
                    SCNAction.playAudio(catchFireSound, waitForCompletion: false),
                    SCNAction.playAudio(ouchSound, waitForCompletion: false),
                    SCNAction.repeatForever(SCNAction.sequence([
                        SCNAction.fadeOpacity(to: 0.01, duration: 2.0),
                        SCNAction.fadeOpacity(to: 1.0, duration: 0.1)
                        ]))
                    ]))
                whiteSmokeEmitter.birthRate = 0
                fireEmitter.birthRate = fireEmitterBirthRate
                smokeEmitter.birthRate = smokeEmitterBirthRate
            } else {
                model.removeAllAudioPlayers()
                model.removeAllActions()
                model.opacity = 1.0
                model.runAction(SCNAction.playAudio(aahSound, waitForCompletion: false))
                
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.0
                whiteSmokeEmitter.birthRate = whiteSmokeEmitterBirthRate
                fireEmitter.birthRate = 0
                smokeEmitter.birthRate = 0
                SCNTransaction.commit()
                
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 5.0
                whiteSmokeEmitter.birthRate = 0
                SCNTransaction.commit()
            }
        }
    }
    
    // MARK: - Controlling the character
    
    private var directionAngle: CGFloat = 0.0 {
        didSet {
            characterOrientation.runAction(
                SCNAction.rotateTo(x: 0.0, y: directionAngle, z: 0.0, duration: 0.1, usesShortestUnitArc:true))
        }
    }
    
    func update(atTime time: TimeInterval, with renderer: SCNSceneRenderer) {
        frameCounter += 1
        
        if shouldResetCharacterPosition {
            shouldResetCharacterPosition = false
            resetCharacterPosition()
            return
        }
        
        var characterVelocity = float3.zero
        
        // setup
        var groundMove = float3.zero
        
        // did the ground moved? 如果有接觸到地板？
        if groundNode != nil {
            let groundPosition = groundNode!.simdWorldPosition
            groundMove = groundPosition - groundNodeLastPosition
        }
//        print("GroundMove:\(groundMove)")
        
//        characterVelocity = float3(groundMove.x, 0, groundMove.z)
        
        let direction = characterDirection(withPointOfView:renderer.pointOfView)
        
        if previousUpdateTime == 0.0 {
            previousUpdateTime = time
        }
        
        let deltaTime = time - previousUpdateTime
        let characterSpeed = CGFloat(deltaTime) * Character.speedFactor * walkSpeed
        let virtualFrameCount = Int(deltaTime / (1 / 60.0))
        previousUpdateTime = time
        
        // move
        if !direction.allZero() {
            characterVelocity = direction * Float(characterSpeed)
            var runModifier = Float(1.0)
            #if os(OSX)
            if NSEvent.modifierFlags.contains(.shift) {
                runModifier = 2.0
            }
            #endif
            walkSpeed = CGFloat(runModifier * simd_length(direction))
            
            // 設定角色旋轉方向 反函數求角度
            directionAngle = CGFloat(atan2f(direction.x, direction.z))
            
            print("directionAngle:\(directionAngle)")
            print("x:\(direction.x), z:\(direction.z), tan:\(directionAngle)")
            
            // 執行角色walk動畫
            isWalking = true
        } else {
            
            // 停止角色walk動畫
            isWalking = false
        }
        
        // put the character on the ground
        let up = float3(0, 1.0, 0)
        var wPosition = characterNode.simdWorldPosition
        // gravity
        
//        print("downwardAcceleration:\(downwardAcceleration), Gravity:\(Character.gravity)")
        
        // 下墜的加速度 要加上重力
        downwardAcceleration -= Character.gravity
        wPosition.y += downwardAcceleration
        let HIT_RANGE = Float(1)
        var p0 = wPosition
        var p1 = wPosition
        
        // 單純向上，向下延伸已取得垂直的接觸面，也就是地板
        p0.y = wPosition.y + up.y * HIT_RANGE
        p1.y = wPosition.y - up.y * HIT_RANGE
        
//        print("p0:\(p0) and p1:\(p1)")
        
        
        
        
        let options: [String: Any] = [
            SCNHitTestOption.backFaceCulling.rawValue: false,
            SCNHitTestOption.categoryBitMask.rawValue: Character.collisionMeshBitMask,
            SCNHitTestOption.ignoreHiddenNodes.rawValue: false]
        
        let hitFrom = SCNVector3.init(p0)
        let hitTo = SCNVector3.init(p1)
        
        
        // rootNode就是Max啦
        let hitResult = renderer.scene!.rootNode.hitTestWithSegment(from: hitFrom, to: hitTo, options: options).first
        
        let wasTouchingTheGroup = groundNode != nil
        groundNode = nil
        var touchesTheGround = false
        let wasBurning = isBurning
        
        if let hit = hitResult {
            let ground = float3.init(hit.worldCoordinates)
            
//            print("groundY:\(ground.y)")
            if wPosition.y <= ground.y + Character.collisionMargin {
                wPosition.y = ground.y + Character.collisionMargin
                if downwardAcceleration < 0 {
                   downwardAcceleration = 0
                }
                groundNode = hit.node
                touchesTheGround = true
                
                //touching lava?
                isBurning = groundNode?.name == "COLL_lava"
            }
        } else {
            // 如果這時候是沒有接觸到地板的狀態
            if wPosition.y < Character.minAltitude {
                wPosition.y = Character.minAltitude
                //reset
                queueResetCharacterPosition()
            }
        }
        
        groundNodeLastPosition = (groundNode != nil) ? groundNode!.simdWorldPosition: float3.zero
        
        //jump -------------------------------------------------------------
        if jumpState == 0 {
            if isJump && touchesTheGround {
                downwardAcceleration += Character.jumpImpulse
                jumpState = 1
                
                model.animationPlayer(forKey: "jump")?.play()
            }
        } else {
            if jumpState == 1 && !isJump {
                jumpState = 2
            }
            
            if downwardAcceleration > 0 {
                for _ in 0..<virtualFrameCount {
                    downwardAcceleration *= jumpState == 1 ? 0.99: 0.2
                }
            }
            
            if touchesTheGround {
                if !wasTouchingTheGroup {
                    model.animationPlayer(forKey: "jump")?.stop(withBlendOutDuration: 0.1)
                    
                    // trigger jump particles if not touching lava
                    if isBurning {
                        model.childNode(withName: "dustEmitter", recursively: true)?.addParticleSystem(jumpDustParticle)
                    } else {
                        // jump in lava again
                        if wasBurning {
                            characterNode.runAction(SCNAction.sequence([
                                SCNAction.playAudio(catchFireSound, waitForCompletion: false),
                                SCNAction.playAudio(ouchSound, waitForCompletion: false)
                                ]))
                        }
                    }
                }
                
                if !isJump {
                    jumpState = 0
                }
            }
        }
        
        if touchesTheGround && !wasTouchingTheGroup && !isBurning && lastStepFrame < frameCounter - 10 {
            // sound
            lastStepFrame = frameCounter
            characterNode.runAction(SCNAction.playAudio(steps[0], waitForCompletion: false))
        }
        
        if wPosition.y < characterNode.simdPosition.y {
            wPosition.y = characterNode.simdPosition.y
        }
        //------------------------------------------------------------------
        
        // progressively update the elevation node when we touch the ground
        if touchesTheGround {
            targetAltitude = wPosition.y
        }
        baseAltitude *= 0.95
        baseAltitude += targetAltitude * 0.05
        
        characterVelocity.y += downwardAcceleration
        if simd_length_squared(characterVelocity) > 10E-4 * 10E-4 {
            let startPosition = characterNode!.presentation.simdWorldPosition + collisionShapeOffsetFromModel
            slideInWorld(fromPosition: startPosition, velocity: characterVelocity)
        }
    }
    
    // MARK: - Animating the character
    
    var isAttacking: Bool {
        return attackCount > 0
    }
    
    func attack() {
        attackCount += 1
        model.animationPlayer(forKey: "spin")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.attackCount -= 1
        }
        spinParticleAttach.addParticleSystem(spinCircleParticle)
    }
    
    var isWalking: Bool = false {
        didSet {
            if oldValue != isWalking {
                // Update node animation.
                if isWalking {
                    model.animationPlayer(forKey: "walk")?.play()
                } else {
                    model.animationPlayer(forKey: "walk")?.stop(withBlendOutDuration: 0.2)
                }
            }
        }
    }
    
    var walkSpeed: CGFloat = 1.0 {
        didSet {
            let burningFactor: CGFloat = isBurning ? 2: 1
            model.animationPlayer(forKey: "walk")?.speed = Character.speedFactor * walkSpeed * burningFactor
        }
    }
    
    func characterDirection(withPointOfView pointOfView: SCNNode?) -> float3 {
        let controllerDir = self.direction
        if controllerDir.allZero() {
            return float3.zero
        }
        
//        print("ControllerDir:\(controllerDir)")
        
        var directionWorld = float3.zero
        if let pov = pointOfView {
            
            // 讓方向的轉換不限於角色的節點
            let p1 = pov.presentation.simdConvertPosition(float3(controllerDir.x, 0.0, controllerDir.y), to: nil)
            let p0 = pov.presentation.simdConvertPosition(float3.zero, to: nil)
            directionWorld = p1 - p0
            directionWorld.y = 0
            if simd_any(directionWorld != float3.zero) {
                let minControllerSpeedFactor = Float(0.2)
                let maxControllerSpeedFactor = Float(1.0)
                let speed = simd_length(controllerDir) * (maxControllerSpeedFactor - minControllerSpeedFactor) + minControllerSpeedFactor
//                print("speed:\(speed)")
                // 調整向量的速度
                directionWorld = speed * simd_normalize(directionWorld)
            }
        }
//        print("directionWorld:\(directionWorld)")
        return directionWorld
    }
    
    func resetCharacterPosition() {
        characterNode.simdPosition = Character.initialPosition
        downwardAcceleration = 0
    }
    
    // MARK: enemy
    
    func didHitEnemy() {
        model.runAction(SCNAction.group(
            [SCNAction.playAudio(hitEnemySound, waitForCompletion: false),
             SCNAction.sequence(
                [SCNAction.wait(duration: 0.5),
                 SCNAction.playAudio(explodeEnemySound, waitForCompletion: false)
                ])
            ]))
    }
    
    func wasTouchedByEnemy() {
        let time = CFAbsoluteTimeGetCurrent()
        if time > lastHitTime + 1 {
            lastHitTime = time
            model.runAction(SCNAction.sequence([
                SCNAction.playAudio(hitSound, waitForCompletion: false),
                SCNAction.repeat(SCNAction.sequence([
                    SCNAction.fadeOpacity(to: 0.01, duration: 0.1),
                    SCNAction.fadeOpacity(to: 1.0, duration: 0.1)
                    ]), count: 4)
                ]))
        }
    }
    
    // MARK: utils
    
    class func loadAnimation(fromSceneNamed sceneName: String) -> SCNAnimationPlayer {
        let scene = SCNScene( named: sceneName )!
        // find top level animation
        var animationPlayer: SCNAnimationPlayer! = nil
        scene.rootNode.enumerateChildNodes { (child, stop) in
            if !child.animationKeys.isEmpty {
                animationPlayer = child.animationPlayer(forKey: child.animationKeys[0])
                stop.pointee = true
            }
        }
        return animationPlayer
    }
    
    // MARK: - physics contact
    func slideInWorld(fromPosition start: float3, velocity: float3) {
//        print("startPostition:\(start), Velocity:\(velocity)")
        let maxSlideIteration: Int = 4
        var iteration = 0
        var stop: Bool = false
        
        var replacementPoint = start
        
        var start = start
        var velocity = velocity
        let options: [SCNPhysicsWorld.TestOption: Any] = [
            SCNPhysicsWorld.TestOption.collisionBitMask: Bitmask.collision.rawValue,
            SCNPhysicsWorld.TestOption.searchMode: SCNPhysicsWorld.TestSearchMode.closest]
        while !stop {
            var from = matrix_identity_float4x4
            from.position = start
            
            var to: matrix_float4x4 = matrix_identity_float4x4
            
            // 利用向量加上位置
            to.position = start + velocity
            
//            print("to:\(to)")
            
            // 確認Max本身的碰撞外觀有沒有和兩個Mat4產生碰撞
            let contacts = physicsWorld!.convexSweepTest(
                with: characterCollisionShape!,
                from: SCNMatrix4.init(from),
                to: SCNMatrix4.init(to),
                options: options)
            if !contacts.isEmpty {
                
//                print("concact:\(contacts.first!)")
                
                // 計算滑落下來的相關數值
                (velocity, start) = handleSlidingAtContact(contacts.first!, position: start, velocity: velocity)
                iteration += 1
//
                if simd_length_squared(velocity) <= (10E-3 * 10E-3) || iteration >= maxSlideIteration {
                    replacementPoint = start
                    stop = true
                }
            } else {
                replacementPoint = start + velocity
                stop = true
            }
        }
        characterNode!.simdWorldPosition = replacementPoint - collisionShapeOffsetFromModel
    }

    private func handleSlidingAtContact(_ closestContact: SCNPhysicsContact, position start: float3, velocity: float3)
        -> (computedVelocity: simd_float3, colliderPositionAtContact: simd_float3) {
            
            
            
        let originalDistance: Float = simd_length(velocity)
        let colliderPositionAtContact = start + Float(closestContact.sweepTestFraction) * velocity
            
            
            
        // Compute the sliding plane.
        let slidePlaneNormal = float3.init(closestContact.contactNormal) //法相量
        let slidePlaneOrigin = float3.init(closestContact.contactPoint)  //法向量中心點，以Concact的座標來看
        let centerOffset = slidePlaneOrigin - colliderPositionAtContact // 因為SlidePlaneOrigin是中心點，所以這是算中心偏差值
            
            
        // Compute destination relative to the point of contact.
        let destinationPoint = slidePlaneOrigin + velocity  // 可能是反彈的點？

        // We now project the destination point onto the sliding plane.
        let distPlane = simd_dot(slidePlaneOrigin, slidePlaneNormal)    //做出目標slide平面

        // Project on plane.
        var t = planeIntersect(planeNormal: slidePlaneNormal, planeDist: distPlane,
                               rayOrigin: destinationPoint, rayDirection: slidePlaneNormal)

        let normalizedVelocity = velocity//velocity * (1.0 / originalDistance)
        let angle = simd_dot(slidePlaneNormal, normalizedVelocity)
            
            
            print("normalizedVelocity:\(normalizedVelocity), angle:\(angle)")
        var frictionCoeff: Float = 0.3
        if fabs(angle) < 0.9 {
            t += 10E-3
            frictionCoeff = 1.0
        }
        let newDestinationPoint = (destinationPoint + t * slidePlaneNormal) - centerOffset

        // Advance start position to nearest point without collision.
        let computedVelocity = frictionCoeff * Float(1.0 - closestContact.sweepTestFraction)
            * originalDistance * simd_normalize(newDestinationPoint - start)

        return (computedVelocity, colliderPositionAtContact)
    }

}
